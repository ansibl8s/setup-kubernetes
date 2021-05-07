# Copyright 2016 Mirantis, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

import inventory
import unittest
from unittest import mock

from collections import OrderedDict
import sys

path = "./contrib/inventory_builder/"
if path not in sys.path:
    sys.path.append(path)

import inventory  # noqa


class TestInventory(unittest.TestCase):
    @mock.patch('inventory.sys')
    def setUp(self, sys_mock):
        sys_mock.exit = mock.Mock()
        super(TestInventory, self).setUp()
        self.data = ['10.90.3.2', '10.90.3.3', '10.90.3.4']
        self.inv = inventory.KubesprayInventory()

    def test_get_ip_from_opts(self):
        optstring = {'ansible_host': '10.90.3.2',
                     'ip': '10.90.3.2',
                     'access_ip': '10.90.3.2'}
        expected = "10.90.3.2"
        result = self.inv.get_ip_from_opts(optstring)
        self.assertEqual(expected, result)

    def test_get_ip_from_opts_invalid(self):
        optstring = "notanaddr=value something random!chars:D"
        self.assertRaisesRegex(ValueError, "IP parameter not found",
                               self.inv.get_ip_from_opts, optstring)

    def test_ensure_required_groups(self):
        groups = ['group1', 'group2']
        self.inv.ensure_required_groups(groups)
        for group in groups:
            self.assertIn(group, self.inv.yaml_config['all']['children'])

    def test_get_host_id(self):
        hostnames = ['node99', 'no99de01', '01node01', 'node1.domain',
                     'node3.xyz123.aaa']
        expected = [99, 1, 1, 1, 3]
        for hostname, expected in zip(hostnames, expected):
            result = self.inv.get_host_id(hostname)
            self.assertEqual(expected, result)

    def test_get_host_id_invalid(self):
        bad_hostnames = ['node', 'no99de', '01node', 'node.111111']
        for hostname in bad_hostnames:
            self.assertRaisesRegex(ValueError, "Host name must end in an",
                                   self.inv.get_host_id, hostname)

    def test_build_hostnames_add_duplicate(self):
        changed_hosts = ['10.90.0.2']
        expected = OrderedDict([('node3',
                                 {'ansible_host': '10.90.0.2',
                                  'ip': '10.90.0.2',
                                  'access_ip': '10.90.0.2'})])
        self.inv.yaml_config['all']['hosts'] = expected
        result = self.inv.build_hostnames(changed_hosts, True)
        self.assertEqual(expected, result)

    def test_build_hostnames_add_two(self):
        changed_hosts = ['10.90.0.2', '10.90.0.3']
        expected = OrderedDict([
            ('node1', {'ansible_host': '10.90.0.2',
                       'ip': '10.90.0.2',
                       'access_ip': '10.90.0.2'}),
            ('node2', {'ansible_host': '10.90.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '10.90.0.3'})])
        self.inv.yaml_config['all']['hosts'] = OrderedDict()
        result = self.inv.build_hostnames(changed_hosts)
        self.assertEqual(expected, result)

    def test_build_hostnames_add_three(self):
        changed_hosts = ['10.90.0.2', '10.90.0.3', '10.90.0.4']
        expected = OrderedDict([
            ('node1', {'ansible_host': '10.90.0.2',
                       'ip': '10.90.0.2',
                       'access_ip': '10.90.0.2'}),
            ('node2', {'ansible_host': '10.90.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '10.90.0.3'}),
            ('node3', {'ansible_host': '10.90.0.4',
                       'ip': '10.90.0.4',
                       'access_ip': '10.90.0.4'})])
        result = self.inv.build_hostnames(changed_hosts)
        self.assertEqual(expected, result)

    def test_build_hostnames_add_one(self):
        changed_hosts = ['10.90.0.2']
        expected = OrderedDict([('node1',
                                 {'ansible_host': '10.90.0.2',
                                  'ip': '10.90.0.2',
                                  'access_ip': '10.90.0.2'})])
        result = self.inv.build_hostnames(changed_hosts)
        self.assertEqual(expected, result)

    def test_build_hostnames_delete_first(self):
        changed_hosts = ['-10.90.0.2']
        existing_hosts = OrderedDict([
            ('node1', {'ansible_host': '10.90.0.2',
                       'ip': '10.90.0.2',
                       'access_ip': '10.90.0.2'}),
            ('node2', {'ansible_host': '10.90.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '10.90.0.3'})])
        self.inv.yaml_config['all']['hosts'] = existing_hosts
        expected = OrderedDict([
            ('node2', {'ansible_host': '10.90.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '10.90.0.3'})])
        result = self.inv.build_hostnames(changed_hosts, True)
        self.assertEqual(expected, result)

    def test_build_hostnames_delete_by_hostname(self):
        changed_hosts = ['-node1']
        existing_hosts = OrderedDict([
            ('node1', {'ansible_host': '10.90.0.2',
                       'ip': '10.90.0.2',
                       'access_ip': '10.90.0.2'}),
            ('node2', {'ansible_host': '10.90.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '10.90.0.3'})])
        self.inv.yaml_config['all']['hosts'] = existing_hosts
        expected = OrderedDict([
            ('node2', {'ansible_host': '10.90.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '10.90.0.3'})])
        result = self.inv.build_hostnames(changed_hosts, True)
        self.assertEqual(expected, result)

    def test_exists_hostname_positive(self):
        hostname = 'node1'
        expected = True
        existing_hosts = OrderedDict([
            ('node1', {'ansible_host': '10.90.0.2',
                       'ip': '10.90.0.2',
                       'access_ip': '10.90.0.2'}),
            ('node2', {'ansible_host': '10.90.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '10.90.0.3'})])
        result = self.inv.exists_hostname(existing_hosts, hostname)
        self.assertEqual(expected, result)

    def test_exists_hostname_negative(self):
        hostname = 'node99'
        expected = False
        existing_hosts = OrderedDict([
            ('node1', {'ansible_host': '10.90.0.2',
                       'ip': '10.90.0.2',
                       'access_ip': '10.90.0.2'}),
            ('node2', {'ansible_host': '10.90.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '10.90.0.3'})])
        result = self.inv.exists_hostname(existing_hosts, hostname)
        self.assertEqual(expected, result)

    def test_exists_ip_positive(self):
        ip = '10.90.0.2'
        expected = True
        existing_hosts = OrderedDict([
            ('node1', {'ansible_host': '10.90.0.2',
                       'ip': '10.90.0.2',
                       'access_ip': '10.90.0.2'}),
            ('node2', {'ansible_host': '10.90.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '10.90.0.3'})])
        result = self.inv.exists_ip(existing_hosts, ip)
        self.assertEqual(expected, result)

    def test_exists_ip_negative(self):
        ip = '10.90.0.200'
        expected = False
        existing_hosts = OrderedDict([
            ('node1', {'ansible_host': '10.90.0.2',
                       'ip': '10.90.0.2',
                       'access_ip': '10.90.0.2'}),
            ('node2', {'ansible_host': '10.90.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '10.90.0.3'})])
        result = self.inv.exists_ip(existing_hosts, ip)
        self.assertEqual(expected, result)

    def test_delete_host_by_ip_positive(self):
        ip = '10.90.0.2'
        expected = OrderedDict([
            ('node2', {'ansible_host': '10.90.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '10.90.0.3'})])
        existing_hosts = OrderedDict([
            ('node1', {'ansible_host': '10.90.0.2',
                       'ip': '10.90.0.2',
                       'access_ip': '10.90.0.2'}),
            ('node2', {'ansible_host': '10.90.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '10.90.0.3'})])
        self.inv.delete_host_by_ip(existing_hosts, ip)
        self.assertEqual(expected, existing_hosts)

    def test_delete_host_by_ip_negative(self):
        ip = '10.90.0.200'
        existing_hosts = OrderedDict([
            ('node1', {'ansible_host': '10.90.0.2',
                       'ip': '10.90.0.2',
                       'access_ip': '10.90.0.2'}),
            ('node2', {'ansible_host': '10.90.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '10.90.0.3'})])
        self.assertRaisesRegex(ValueError, "Unable to find host",
                               self.inv.delete_host_by_ip, existing_hosts, ip)

    def test_purge_invalid_hosts(self):
        proper_hostnames = ['node1', 'node2']
        bad_host = 'doesnotbelong2'
        existing_hosts = OrderedDict([
            ('node1', {'ansible_host': '10.90.0.2',
                       'ip': '10.90.0.2',
                       'access_ip': '10.90.0.2'}),
            ('node2', {'ansible_host': '10.90.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '10.90.0.3'}),
            ('doesnotbelong2', {'whateveropts=ilike'})])
        self.inv.yaml_config['all']['hosts'] = existing_hosts
        self.inv.purge_invalid_hosts(proper_hostnames)
        self.assertNotIn(
            bad_host, self.inv.yaml_config['all']['hosts'].keys())

    def test_add_host_to_group(self):
        group = 'etcd'
        host = 'node1'
        opts = {'ip': '10.90.0.2'}

        self.inv.add_host_to_group(group, host, opts)
        self.assertEqual(
            self.inv.yaml_config['all']['children'][group]['hosts'].get(host),
            None)

    def test_set_kube_control_plane(self):
        group = 'kube_control_plane'
        host = 'node1'

        self.inv.set_kube_control_plane([host])
        self.assertIn(
            host, self.inv.yaml_config['all']['children'][group]['hosts'])

    def test_set_all(self):
        hosts = OrderedDict([
            ('node1', 'opt1'),
            ('node2', 'opt2')])

        self.inv.set_all(hosts)
        for host, opt in hosts.items():
            self.assertEqual(
                self.inv.yaml_config['all']['hosts'].get(host), opt)

    def test_set_k8s_cluster(self):
        group = 'k8s_cluster'
        expected_hosts = ['kube_node', 'kube_control_plane']

        self.inv.set_k8s_cluster()
        for host in expected_hosts:
            self.assertIn(
                host,
                self.inv.yaml_config['all']['children'][group]['children'])

    def test_set_kube_node(self):
        group = 'kube_node'
        host = 'node1'

        self.inv.set_kube_node([host])
        self.assertIn(
            host, self.inv.yaml_config['all']['children'][group]['hosts'])

    def test_set_etcd(self):
        group = 'etcd'
        host = 'node1'

        self.inv.set_etcd([host])
        self.assertIn(
            host, self.inv.yaml_config['all']['children'][group]['hosts'])

    def test_scale_scenario_one(self):
        num_nodes = 50
        hosts = OrderedDict()

        for hostid in range(1, num_nodes+1):
            hosts["node" + str(hostid)] = ""

        self.inv.set_all(hosts)
        self.inv.set_etcd(list(hosts.keys())[0:3])
        self.inv.set_kube_control_plane(list(hosts.keys())[0:2])
        self.inv.set_kube_node(hosts.keys())
        for h in range(3):
            self.assertFalse(
                list(hosts.keys())[h] in
                self.inv.yaml_config['all']['children']['kube_node']['hosts'])

    def test_scale_scenario_two(self):
        num_nodes = 500
        hosts = OrderedDict()

        for hostid in range(1, num_nodes+1):
            hosts["node" + str(hostid)] = ""

        self.inv.set_all(hosts)
        self.inv.set_etcd(list(hosts.keys())[0:3])
        self.inv.set_kube_control_plane(list(hosts.keys())[3:5])
        self.inv.set_kube_node(hosts.keys())
        for h in range(5):
            self.assertFalse(
                list(hosts.keys())[h] in
                self.inv.yaml_config['all']['children']['kube_node']['hosts'])

    def test_range2ips_range(self):
        changed_hosts = ['10.90.0.2', '10.90.0.4-10.90.0.6', '10.90.0.8']
        expected = ['10.90.0.2',
                    '10.90.0.4',
                    '10.90.0.5',
                    '10.90.0.6',
                    '10.90.0.8']
        result = self.inv.range2ips(changed_hosts)
        self.assertEqual(expected, result)

    def test_range2ips_incorrect_range(self):
        host_range = ['10.90.0.4-a.9b.c.e']
        self.assertRaisesRegex(Exception, "Range of ip_addresses isn't valid",
                               self.inv.range2ips, host_range)

    def test_build_hostnames_create_with_one_different_ips(self):
        changed_hosts = ['10.90.0.2,192.168.0.2']
        expected = OrderedDict([('node1',
                                 {'ansible_host': '192.168.0.2',
                                  'ip': '10.90.0.2',
                                  'access_ip': '192.168.0.2'})])
        result = self.inv.build_hostnames(changed_hosts)
        self.assertEqual(expected, result)

    def test_build_hostnames_create_with_two_different_ips(self):
        changed_hosts = ['10.90.0.2,192.168.0.2', '10.90.0.3,192.168.0.3']
        expected = OrderedDict([
            ('node1', {'ansible_host': '192.168.0.2',
                       'ip': '10.90.0.2',
                       'access_ip': '192.168.0.2'}),
            ('node2', {'ansible_host': '192.168.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '192.168.0.3'})])
        result = self.inv.build_hostnames(changed_hosts)
        self.assertEqual(expected, result)

    def test_build_hostnames_create_with_three_different_ips(self):
        changed_hosts = ['10.90.0.2,192.168.0.2',
                         '10.90.0.3,192.168.0.3',
                         '10.90.0.4,192.168.0.4']
        expected = OrderedDict([
            ('node1', {'ansible_host': '192.168.0.2',
                       'ip': '10.90.0.2',
                       'access_ip': '192.168.0.2'}),
            ('node2', {'ansible_host': '192.168.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '192.168.0.3'}),
            ('node3', {'ansible_host': '192.168.0.4',
                       'ip': '10.90.0.4',
                       'access_ip': '192.168.0.4'})])
        result = self.inv.build_hostnames(changed_hosts)
        self.assertEqual(expected, result)

    def test_build_hostnames_overwrite_one_with_different_ips(self):
        changed_hosts = ['10.90.0.2,192.168.0.2']
        expected = OrderedDict([('node1',
                                 {'ansible_host': '192.168.0.2',
                                  'ip': '10.90.0.2',
                                  'access_ip': '192.168.0.2'})])
        existing = OrderedDict([('node5',
                                 {'ansible_host': '192.168.0.5',
                                  'ip': '10.90.0.5',
                                  'access_ip': '192.168.0.5'})])
        self.inv.yaml_config['all']['hosts'] = existing
        result = self.inv.build_hostnames(changed_hosts)
        self.assertEqual(expected, result)

    def test_build_hostnames_overwrite_three_with_different_ips(self):
        changed_hosts = ['10.90.0.2,192.168.0.2']
        expected = OrderedDict([('node1',
                                 {'ansible_host': '192.168.0.2',
                                  'ip': '10.90.0.2',
                                  'access_ip': '192.168.0.2'})])
        existing = OrderedDict([
            ('node3', {'ansible_host': '192.168.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '192.168.0.3'}),
            ('node4', {'ansible_host': '192.168.0.4',
                       'ip': '10.90.0.4',
                       'access_ip': '192.168.0.4'}),
            ('node5', {'ansible_host': '192.168.0.5',
                       'ip': '10.90.0.5',
                       'access_ip': '192.168.0.5'})])
        self.inv.yaml_config['all']['hosts'] = existing
        result = self.inv.build_hostnames(changed_hosts)
        self.assertEqual(expected, result)

    def test_build_hostnames_different_ips_add_duplicate(self):
        changed_hosts = ['10.90.0.2,192.168.0.2']
        expected = OrderedDict([('node3',
                                 {'ansible_host': '192.168.0.2',
                                  'ip': '10.90.0.2',
                                  'access_ip': '192.168.0.2'})])
        existing = expected
        self.inv.yaml_config['all']['hosts'] = existing
        result = self.inv.build_hostnames(changed_hosts, True)
        self.assertEqual(expected, result)

    def test_build_hostnames_add_two_different_ips_into_one_existing(self):
        changed_hosts = ['10.90.0.3,192.168.0.3', '10.90.0.4,192.168.0.4']
        expected = OrderedDict([
            ('node2', {'ansible_host': '192.168.0.2',
                       'ip': '10.90.0.2',
                       'access_ip': '192.168.0.2'}),
            ('node3', {'ansible_host': '192.168.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '192.168.0.3'}),
            ('node4', {'ansible_host': '192.168.0.4',
                       'ip': '10.90.0.4',
                       'access_ip': '192.168.0.4'})])

        existing = OrderedDict([
            ('node2', {'ansible_host': '192.168.0.2',
                       'ip': '10.90.0.2',
                       'access_ip': '192.168.0.2'})])
        self.inv.yaml_config['all']['hosts'] = existing
        result = self.inv.build_hostnames(changed_hosts, True)
        self.assertEqual(expected, result)

    def test_build_hostnames_add_two_different_ips_into_two_existing(self):
        changed_hosts = ['10.90.0.4,192.168.0.4', '10.90.0.5,192.168.0.5']
        expected = OrderedDict([
            ('node2', {'ansible_host': '192.168.0.2',
                       'ip': '10.90.0.2',
                       'access_ip': '192.168.0.2'}),
            ('node3', {'ansible_host': '192.168.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '192.168.0.3'}),
            ('node4', {'ansible_host': '192.168.0.4',
                       'ip': '10.90.0.4',
                       'access_ip': '192.168.0.4'}),
            ('node5', {'ansible_host': '192.168.0.5',
                       'ip': '10.90.0.5',
                       'access_ip': '192.168.0.5'})])

        existing = OrderedDict([
            ('node2', {'ansible_host': '192.168.0.2',
                       'ip': '10.90.0.2',
                       'access_ip': '192.168.0.2'}),
            ('node3', {'ansible_host': '192.168.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '192.168.0.3'})])
        self.inv.yaml_config['all']['hosts'] = existing
        result = self.inv.build_hostnames(changed_hosts, True)
        self.assertEqual(expected, result)

    def test_build_hostnames_add_two_different_ips_into_three_existing(self):
        changed_hosts = ['10.90.0.5,192.168.0.5', '10.90.0.6,192.168.0.6']
        expected = OrderedDict([
            ('node2', {'ansible_host': '192.168.0.2',
                       'ip': '10.90.0.2',
                       'access_ip': '192.168.0.2'}),
            ('node3', {'ansible_host': '192.168.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '192.168.0.3'}),
            ('node4', {'ansible_host': '192.168.0.4',
                       'ip': '10.90.0.4',
                       'access_ip': '192.168.0.4'}),
            ('node5', {'ansible_host': '192.168.0.5',
                       'ip': '10.90.0.5',
                       'access_ip': '192.168.0.5'}),
            ('node6', {'ansible_host': '192.168.0.6',
                       'ip': '10.90.0.6',
                       'access_ip': '192.168.0.6'})])

        existing = OrderedDict([
            ('node2', {'ansible_host': '192.168.0.2',
                       'ip': '10.90.0.2',
                       'access_ip': '192.168.0.2'}),
            ('node3', {'ansible_host': '192.168.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '192.168.0.3'}),
            ('node4', {'ansible_host': '192.168.0.4',
                       'ip': '10.90.0.4',
                       'access_ip': '192.168.0.4'})])
        self.inv.yaml_config['all']['hosts'] = existing
        result = self.inv.build_hostnames(changed_hosts, True)
        self.assertEqual(expected, result)

    # Add two IP addresses into a config that has
    # three already defined IP addresses. One of the IP addresses
    # is a duplicate.
    def test_build_hostnames_add_two_duplicate_one_overlap(self):
        changed_hosts = ['10.90.0.4,192.168.0.4', '10.90.0.5,192.168.0.5']
        expected = OrderedDict([
            ('node2', {'ansible_host': '192.168.0.2',
                       'ip': '10.90.0.2',
                       'access_ip': '192.168.0.2'}),
            ('node3', {'ansible_host': '192.168.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '192.168.0.3'}),
            ('node4', {'ansible_host': '192.168.0.4',
                       'ip': '10.90.0.4',
                       'access_ip': '192.168.0.4'}),
            ('node5', {'ansible_host': '192.168.0.5',
                       'ip': '10.90.0.5',
                       'access_ip': '192.168.0.5'})])

        existing = OrderedDict([
            ('node2', {'ansible_host': '192.168.0.2',
                       'ip': '10.90.0.2',
                       'access_ip': '192.168.0.2'}),
            ('node3', {'ansible_host': '192.168.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '192.168.0.3'}),
            ('node4', {'ansible_host': '192.168.0.4',
                       'ip': '10.90.0.4',
                       'access_ip': '192.168.0.4'})])
        self.inv.yaml_config['all']['hosts'] = existing
        result = self.inv.build_hostnames(changed_hosts, True)
        self.assertEqual(expected, result)

    # Add two duplicate IP addresses into a config that has
    # three already defined IP addresses
    def test_build_hostnames_add_two_duplicate_two_overlap(self):
        changed_hosts = ['10.90.0.3,192.168.0.3', '10.90.0.4,192.168.0.4']
        expected = OrderedDict([
            ('node2', {'ansible_host': '192.168.0.2',
                       'ip': '10.90.0.2',
                       'access_ip': '192.168.0.2'}),
            ('node3', {'ansible_host': '192.168.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '192.168.0.3'}),
            ('node4', {'ansible_host': '192.168.0.4',
                       'ip': '10.90.0.4',
                       'access_ip': '192.168.0.4'})])

        existing = OrderedDict([
            ('node2', {'ansible_host': '192.168.0.2',
                       'ip': '10.90.0.2',
                       'access_ip': '192.168.0.2'}),
            ('node3', {'ansible_host': '192.168.0.3',
                       'ip': '10.90.0.3',
                       'access_ip': '192.168.0.3'}),
            ('node4', {'ansible_host': '192.168.0.4',
                       'ip': '10.90.0.4',
                       'access_ip': '192.168.0.4'})])
        self.inv.yaml_config['all']['hosts'] = existing
        result = self.inv.build_hostnames(changed_hosts, True)
        self.assertEqual(expected, result)
