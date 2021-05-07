#!/usr/bin/env python3
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Usage: inventory.py ip1 [ip2 ...]
# Examples: inventory.py 10.10.1.3 10.10.1.4 10.10.1.5
#
# Advanced usage:
# Add another host after initial creation: inventory.py 10.10.1.5
# Add range of hosts: inventory.py 10.10.1.3-10.10.1.5
# Add hosts with different ip and access ip:
# inventory.py 10.0.0.1,192.168.10.1 10.0.0.2,192.168.10.2 10.0.0.3,192.168.1.3
# Add hosts with a specific hostname, ip, and optional access ip:
# inventory.py first,10.0.0.1,192.168.10.1 second,10.0.0.2 last,10.0.0.3
# Delete a host: inventory.py -10.10.1.3
# Delete a host by id: inventory.py -node1
#
# Load a YAML or JSON file with inventory data: inventory.py load hosts.yaml
# YAML file should be in the following format:
#    group1:
#      host1:
#        ip: X.X.X.X
#        var: val
#    group2:
#      host2:
#        ip: X.X.X.X

from collections import OrderedDict
from ipaddress import ip_address
from ruamel.yaml import YAML

import os
import re
import subprocess
import sys

ROLES = ['all', 'kube_control_plane', 'kube_node', 'etcd', 'k8s_cluster',
         'calico_rr']
PROTECTED_NAMES = ROLES
AVAILABLE_COMMANDS = ['help', 'print_cfg', 'print_ips', 'print_hostnames',
                      'load', 'add']
_boolean_states = {'1': True, 'yes': True, 'true': True, 'on': True,
                   '0': False, 'no': False, 'false': False, 'off': False}
yaml = YAML()
yaml.Representer.add_representer(OrderedDict, yaml.Representer.represent_dict)


def get_var_as_bool(name, default):
    value = os.environ.get(name, '')
    return _boolean_states.get(value.lower(), default)

# Configurable as shell vars start


CONFIG_FILE = os.environ.get("CONFIG_FILE", "./inventory/sample/hosts.yaml")
# Remove the reference of KUBE_MASTERS after some deprecation cycles.
KUBE_CONTROL_HOSTS = int(os.environ.get("KUBE_CONTROL_HOSTS",
                         os.environ.get("KUBE_MASTERS", 2)))
# Reconfigures cluster distribution at scale
SCALE_THRESHOLD = int(os.environ.get("SCALE_THRESHOLD", 50))
MASSIVE_SCALE_THRESHOLD = int(os.environ.get("MASSIVE_SCALE_THRESHOLD", 200))

DEBUG = get_var_as_bool("DEBUG", True)
HOST_PREFIX = os.environ.get("HOST_PREFIX", "node")
USE_REAL_HOSTNAME = get_var_as_bool("USE_REAL_HOSTNAME", False)

# Configurable as shell vars end


class KubesprayInventory(object):

    def __init__(self, changed_hosts=None, config_file=None):
        self.config_file = config_file
        self.yaml_config = {}
        loadPreviousConfig = False
        # See whether there are any commands to process
        if changed_hosts and changed_hosts[0] in AVAILABLE_COMMANDS:
            if changed_hosts[0] == "add":
                loadPreviousConfig = True
                changed_hosts = changed_hosts[1:]
            else:
                self.parse_command(changed_hosts[0], changed_hosts[1:])
                sys.exit(0)

        # If the user wants to remove a node, we need to load the config anyway
        if changed_hosts and changed_hosts[0][0] == "-":
            loadPreviousConfig = True

        if self.config_file and loadPreviousConfig:  # Load previous YAML file
            try:
                self.hosts_file = open(config_file, 'r')
                self.yaml_config = yaml.load(self.hosts_file)
            except OSError as e:
                # I am assuming we are catching "cannot open file" exceptions
                print(e)
                sys.exit(1)

        self.ensure_required_groups(ROLES)

        if changed_hosts:
            changed_hosts = self.range2ips(changed_hosts)
            self.hosts = self.build_hostnames(changed_hosts,
                                              loadPreviousConfig)
            self.purge_invalid_hosts(self.hosts.keys(), PROTECTED_NAMES)
            self.set_all(self.hosts)
            self.set_k8s_cluster()
            etcd_hosts_count = 3 if len(self.hosts.keys()) >= 3 else 1
            self.set_etcd(list(self.hosts.keys())[:etcd_hosts_count])
            if len(self.hosts) >= SCALE_THRESHOLD:
                self.set_kube_control_plane(list(self.hosts.keys())[
                    etcd_hosts_count:(etcd_hosts_count + KUBE_CONTROL_HOSTS)])
            else:
                self.set_kube_control_plane(
                  list(self.hosts.keys())[:KUBE_CONTROL_HOSTS])
            self.set_kube_node(self.hosts.keys())
            if len(self.hosts) >= SCALE_THRESHOLD:
                self.set_calico_rr(list(self.hosts.keys())[:etcd_hosts_count])
        else:  # Show help if no options
            self.show_help()
            sys.exit(0)

        self.write_config(self.config_file)

    def write_config(self, config_file):
        if config_file:
            with open(self.config_file, 'w') as f:
                yaml.dump(self.yaml_config, f)

        else:
            print("WARNING: Unable to save config. Make sure you set "
                  "CONFIG_FILE env var.")

    def debug(self, msg):
        if DEBUG:
            print("DEBUG: {0}".format(msg))

    def get_ip_from_opts(self, optstring):
        if 'ip' in optstring:
            return optstring['ip']
        else:
            raise ValueError("IP parameter not found in options")

    def ensure_required_groups(self, groups):
        for group in groups:
            if group == 'all':
                self.debug("Adding group {0}".format(group))
                if group not in self.yaml_config:
                    all_dict = OrderedDict([('hosts', OrderedDict({})),
                                            ('children', OrderedDict({}))])
                    self.yaml_config = {'all': all_dict}
            else:
                self.debug("Adding group {0}".format(group))
                if group not in self.yaml_config['all']['children']:
                    self.yaml_config['all']['children'][group] = {'hosts': {}}

    def get_host_id(self, host):
        '''Returns integer host ID (without padding) from a given hostname.'''
        try:
            short_hostname = host.split('.')[0]
            return int(re.findall("\\d+$", short_hostname)[-1])
        except IndexError:
            raise ValueError("Host name must end in an integer")

    # Keeps already specified hosts,
    # and adds or removes the hosts provided as an argument
    def build_hostnames(self, changed_hosts, loadPreviousConfig=False):
        existing_hosts = OrderedDict()
        highest_host_id = 0
        # Load already existing hosts from the YAML
        if loadPreviousConfig:
            try:
                for host in self.yaml_config['all']['hosts']:
                    # Read configuration of an existing host
                    hostConfig = self.yaml_config['all']['hosts'][host]
                    existing_hosts[host] = hostConfig
                    # If the existing host seems
                    # to have been created automatically, detect its ID
                    if host.startswith(HOST_PREFIX):
                        host_id = self.get_host_id(host)
                        if host_id > highest_host_id:
                            highest_host_id = host_id
            except Exception as e:
                # I am assuming we are catching automatically
                # created hosts without IDs
                print(e)
                sys.exit(1)

        # FIXME(mattymo): Fix condition where delete then add reuses highest id
        next_host_id = highest_host_id + 1
        next_host = ""

        all_hosts = existing_hosts.copy()
        for host in changed_hosts:
            # Delete the host from config the hostname/IP has a "-" prefix
            if host[0] == "-":
                realhost = host[1:]
                if self.exists_hostname(all_hosts, realhost):
                    self.debug("Marked {0} for deletion.".format(realhost))
                    all_hosts.pop(realhost)
                elif self.exists_ip(all_hosts, realhost):
                    self.debug("Marked {0} for deletion.".format(realhost))
                    self.delete_host_by_ip(all_hosts, realhost)
            # Host/Argument starts with a digit,
            # then we assume its an IP address
            elif host[0].isdigit():
                if ',' in host:
                    ip, access_ip = host.split(',')
                else:
                    ip = host
                    access_ip = host
                if self.exists_hostname(all_hosts, host):
                    self.debug("Skipping existing host {0}.".format(host))
                    continue
                elif self.exists_ip(all_hosts, ip):
                    self.debug("Skipping existing host {0}.".format(ip))
                    continue

                if USE_REAL_HOSTNAME:
                    cmd = ("ssh -oStrictHostKeyChecking=no "
                           + access_ip + " 'hostname -s'")
                    next_host = subprocess.check_output(cmd, shell=True)
                    next_host = next_host.strip().decode('ascii')
                else:
                    # Generates a hostname because we have only an IP address
                    next_host = "{0}{1}".format(HOST_PREFIX, next_host_id)
                    next_host_id += 1
                # Uses automatically generated node name
                # in case we dont provide it.
                all_hosts[next_host] = {'ansible_host': access_ip,
                                        'ip': ip,
                                        'access_ip': access_ip}
            # Host/Argument starts with a letter, then we assume its a hostname
            elif host[0].isalpha():
                if ',' in host:
                    try:
                        hostname, ip, access_ip = host.split(',')
                    except Exception:
                        hostname, ip = host.split(',')
                        access_ip = ip
                if self.exists_hostname(all_hosts, host):
                    self.debug("Skipping existing host {0}.".format(host))
                    continue
                elif self.exists_ip(all_hosts, ip):
                    self.debug("Skipping existing host {0}.".format(ip))
                    continue
                all_hosts[hostname] = {'ansible_host': access_ip,
                                       'ip': ip,
                                       'access_ip': access_ip}
        return all_hosts

    # Expand IP ranges into individual addresses
    def range2ips(self, hosts):
        reworked_hosts = []

        def ips(start_address, end_address):
            try:
                # Python 3.x
                start = int(ip_address(start_address))
                end = int(ip_address(end_address))
            except Exception:
                # Python 2.7
                start = int(ip_address(str(start_address)))
                end = int(ip_address(str(end_address)))
            return [ip_address(ip).exploded for ip in range(start, end + 1)]

        for host in hosts:
            if '-' in host and not (host.startswith('-') or host[0].isalpha()):
                start, end = host.strip().split('-')
                try:
                    reworked_hosts.extend(ips(start, end))
                except ValueError:
                    raise Exception("Range of ip_addresses isn't valid")
            else:
                reworked_hosts.append(host)
        return reworked_hosts

    def exists_hostname(self, existing_hosts, hostname):
        return hostname in existing_hosts.keys()

    def exists_ip(self, existing_hosts, ip):
        for host_opts in existing_hosts.values():
            if ip == self.get_ip_from_opts(host_opts):
                return True
        return False

    def delete_host_by_ip(self, existing_hosts, ip):
        for hostname, host_opts in existing_hosts.items():
            if ip == self.get_ip_from_opts(host_opts):
                del existing_hosts[hostname]
                return
        raise ValueError("Unable to find host by IP: {0}".format(ip))

    def purge_invalid_hosts(self, hostnames, protected_names=[]):
        for role in self.yaml_config['all']['children']:
            if role != 'k8s_cluster' and self.yaml_config['all']['children'][role]['hosts']:  # noqa
                all_hosts = self.yaml_config['all']['children'][role]['hosts'].copy()  # noqa
                for host in all_hosts.keys():
                    if host not in hostnames and host not in protected_names:
                        self.debug(
                            "Host {0} removed from role {1}".format(host, role))  # noqa
                        del self.yaml_config['all']['children'][role]['hosts'][host]  # noqa
        # purge from all
        if self.yaml_config['all']['hosts']:
            all_hosts = self.yaml_config['all']['hosts'].copy()
            for host in all_hosts.keys():
                if host not in hostnames and host not in protected_names:
                    self.debug("Host {0} removed from role all".format(host))
                    del self.yaml_config['all']['hosts'][host]

    def add_host_to_group(self, group, host, opts=""):
        self.debug("adding host {0} to group {1}".format(host, group))
        if group == 'all':
            if self.yaml_config['all']['hosts'] is None:
                self.yaml_config['all']['hosts'] = {host: None}
            self.yaml_config['all']['hosts'][host] = opts
        elif group != 'k8s_cluster:children':
            if self.yaml_config['all']['children'][group]['hosts'] is None:
                self.yaml_config['all']['children'][group]['hosts'] = {
                    host: None}
            else:
                self.yaml_config['all']['children'][group]['hosts'][host] = None  # noqa

    def set_kube_control_plane(self, hosts):
        for host in hosts:
            self.add_host_to_group('kube_control_plane', host)

    def set_all(self, hosts):
        for host, opts in hosts.items():
            self.add_host_to_group('all', host, opts)

    def set_k8s_cluster(self):
        k8s_cluster = {'children': {'kube_control_plane': None,
                                    'kube_node': None}}
        self.yaml_config['all']['children']['k8s_cluster'] = k8s_cluster

    def set_calico_rr(self, hosts):
        for host in hosts:
            if host in self.yaml_config['all']['children']['kube_control_plane']: # noqa
                self.debug("Not adding {0} to calico_rr group because it "
                           "conflicts with kube_control_plane "
                           "group".format(host))
                continue
            if host in self.yaml_config['all']['children']['kube_node']:
                self.debug("Not adding {0} to calico_rr group because it "
                           "conflicts with kube_node group".format(host))
                continue
            self.add_host_to_group('calico_rr', host)

    def set_kube_node(self, hosts):
        for host in hosts:
            if len(self.yaml_config['all']['hosts']) >= SCALE_THRESHOLD:
                if host in self.yaml_config['all']['children']['etcd']['hosts']:  # noqa
                    self.debug("Not adding {0} to kube_node group because of "
                               "scale deployment and host is in etcd "
                               "group.".format(host))
                    continue
            if len(self.yaml_config['all']['hosts']) >= MASSIVE_SCALE_THRESHOLD:  # noqa
                if host in self.yaml_config['all']['children']['kube_control_plane']['hosts']:  # noqa
                    self.debug("Not adding {0} to kube_node group because of "
                               "scale deployment and host is in "
                               "kube_control_plane group.".format(host))
                    continue
            self.add_host_to_group('kube_node', host)

    def set_etcd(self, hosts):
        for host in hosts:
            self.add_host_to_group('etcd', host)

    def load_file(self, files=None):
        '''Directly loads JSON to inventory.'''

        if not files:
            raise Exception("No input file specified.")

        import json

        for filename in list(files):
            # Try JSON
            try:
                with open(filename, 'r') as f:
                    data = json.load(f)
            except ValueError:
                raise Exception("Cannot read %s as JSON, or CSV", filename)

            self.ensure_required_groups(ROLES)
            self.set_k8s_cluster()
            for group, hosts in data.items():
                self.ensure_required_groups([group])
                for host, opts in hosts.items():
                    optstring = {'ansible_host': opts['ip'],
                                 'ip': opts['ip'],
                                 'access_ip': opts['ip']}
                    self.add_host_to_group('all', host, optstring)
                    self.add_host_to_group(group, host)
            self.write_config(self.config_file)

    def parse_command(self, command, args=None):
        if command == 'help':
            self.show_help()
        elif command == 'print_cfg':
            self.print_config()
        elif command == 'print_ips':
            self.print_ips()
        elif command == 'print_hostnames':
            self.print_hostnames()
        elif command == 'load':
            self.load_file(args)
        else:
            raise Exception("Invalid command specified.")

    def show_help(self):
        help_text = '''Usage: inventory.py ip1 [ip2 ...]
Examples: inventory.py 10.10.1.3 10.10.1.4 10.10.1.5

Available commands:
help - Display this message
print_cfg - Write inventory file to stdout
print_ips - Write a space-delimited list of IPs from "all" group
print_hostnames - Write a space-delimited list of Hostnames from "all" group
add - Adds specified hosts into an already existing inventory

Advanced usage:
Create new or overwrite old inventory file: inventory.py 10.10.1.5
Add another host after initial creation: inventory.py add 10.10.1.6
Add range of hosts: inventory.py 10.10.1.3-10.10.1.5
Add hosts with different ip and access ip: inventory.py 10.0.0.1,192.168.10.1 10.0.0.2,192.168.10.2 10.0.0.3,192.168.10.3
Add hosts with a specific hostname, ip, and optional access ip: first,10.0.0.1,192.168.10.1 second,10.0.0.2 last,10.0.0.3
Delete a host: inventory.py -10.10.1.3
Delete a host by id: inventory.py -node1

Configurable env vars:
DEBUG                   Enable debug printing. Default: True
CONFIG_FILE             File to write config to Default: ./inventory/sample/hosts.yaml
HOST_PREFIX             Host prefix for generated hosts. Default: node
KUBE_CONTROL_HOSTS      Set the number of kube-control-planes. Default: 2
SCALE_THRESHOLD         Separate ETCD role if # of nodes >= 50
MASSIVE_SCALE_THRESHOLD Separate K8s control-plane and ETCD if # of nodes >= 200
'''  # noqa
        print(help_text)

    def print_config(self):
        yaml.dump(self.yaml_config, sys.stdout)

    def print_hostnames(self):
        print(' '.join(self.yaml_config['all']['hosts'].keys()))

    def print_ips(self):
        ips = []
        for host, opts in self.yaml_config['all']['hosts'].items():
            ips.append(self.get_ip_from_opts(opts))
        print(' '.join(ips))


def main(argv=None):
    if not argv:
        argv = sys.argv[1:]
    KubesprayInventory(argv, CONFIG_FILE)


if __name__ == "__main__":
    sys.exit(main())
