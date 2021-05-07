# Kubespray (kubespray) in own ansible playbooks repo

1. Fork [kubespray repo](https://github.com/kubernetes-sigs/kubespray) to your personal/organisation account on github.
   Note:
     * All forked public repos at github will be also public, so **never commit sensitive data to your public forks**.
     * List of all forked repos could be retrieved from github page of original project.

2. Add **forked repo** as submodule to desired folder in your existent ansible repo(for example 3d/kubespray):
  ```git submodule add https://github.com/YOUR_GITHUB/kubespray.git kubespray```
  Git will create `.gitmodules` file in your existent ansible repo:

   ```ini
   [submodule "3d/kubespray"]
         path = 3d/kubespray
         url = https://github.com/YOUR_GITHUB/kubespray.git
   ```

3. Configure git to show submodule status:
```git config --global status.submoduleSummary true```

4. Add *original* kubespray repo as upstream:
```cd kubespray && git remote add upstream https://github.com/kubernetes-sigs/kubespray.git```

5. Sync your master branch with upstream:

   ```ShellSession
      git checkout master
      git fetch upstream
      git merge upstream/master
      git push origin master
   ```

6. Create a new branch which you will use in your working environment:
```git checkout -b work```
    ***Never*** use master branch of your repository for your commits.

7. Modify path to library and roles in your ansible.cfg file (role naming should be unique, you may have to rename your existent roles if they have same names as kubespray project):

   ```ini
   ...
   library       = 3d/kubespray/library/
   roles_path    = 3d/kubespray/roles/
   ...
   ```

8. Copy and modify configs from kubespray `group_vars` folder to corresponding `group_vars` folder in your existent project.
You could rename *all.yml* config to something else, i.e. *kubespray.yml* and create corresponding group in your inventory file, which will include all hosts groups related to kubernetes setup.

9. Modify your ansible inventory file by adding mapping of your existent groups (if any) to kubespray naming.
   For example:

   ```ini
     ...
     #Kargo groups:
     [kube_node:children]
     kubenode

     [k8s_cluster:children]
     kubernetes

     [etcd:children]
     kubemaster
     kubemaster-ha

     [kube_control_plane:children]
     kubemaster
     kubemaster-ha

     [kubespray:children]
     kubernetes
     ```

     * Last entry here needed to apply kubespray.yml config file, renamed from all.yml of kubespray project.

10. Now you can include kubespray tasks in you existent playbooks by including cluster.yml file:

     ```yml
     - name: Include kubespray tasks
       include: 3d/kubespray/cluster.yml
     ```

     Or your could copy separate tasks from cluster.yml into your ansible repository.

11. Commit changes to your ansible repo. Keep in mind, that submodule folder is just a link to the git commit hash of your forked repo.
When you update your "work" branch you need to commit changes to ansible repo as well.
Other members of your team should use ```git submodule sync```, ```git submodule update --init``` to get actual code from submodule.

## Contributing

If you made useful changes or fixed a bug in existent kubespray repo, use this flow for PRs to original kubespray repo.

1. Sign the [CNCF CLA](https://git.k8s.io/community/CLA.md).

2. Change working directory to git submodule directory (3d/kubespray).

3. Setup desired user.name and user.email for submodule.
If kubespray is only one submodule in your repo you could use something like:
```git submodule foreach --recursive 'git config user.name "First Last" && git config user.email "your-email-addres@used.for.cncf"'```

4. Sync with upstream master:

   ```ShellSession
    git fetch upstream
    git merge upstream/master
    git push origin master
     ```

5. Create new branch for the specific fixes that you want to contribute:
```git checkout -b fixes-name-date-index```
Branch name should be self explaining to you, adding date and/or index will help you to track/delete your old PRs.

6. Find git hash of your commit in "work" repo and apply it to newly created "fix" repo:

     ```ShellSession
     git cherry-pick <COMMIT_HASH>
     ```

7. If you have several temporary-stage commits - squash them using [```git rebase -i```](https://eli.thegreenplace.net/2014/02/19/squashing-github-pull-requests-into-a-single-commit)
Also you could use interactive rebase (```git rebase -i HEAD~10```) to delete commits which you don't want to contribute into original repo.

8. When your changes is in place, you need to check upstream repo one more time because it could be changed during your work.
Check that you're on correct branch:
```git status```
And pull changes from upstream (if any):
```git pull --rebase upstream master```

9. Now push your changes to your **fork** repo with ```git push```. If your branch doesn't exists on github, git will propose you to use something like ```git push --set-upstream origin fixes-name-date-index```.

10. Open you forked repo in browser, on the main page you will see proposition to create pull request for your newly created branch. Check proposed diff of your PR. If something is wrong you could safely delete "fix" branch on github using ```git push origin --delete fixes-name-date-index```, ```git branch -D fixes-name-date-index``` and start whole process from the beginning.
If everything is fine - add description about your changes (what they do and why they're needed) and confirm pull request creation.
