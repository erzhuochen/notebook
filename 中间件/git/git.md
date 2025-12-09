# git 加速

关掉 PC Manager 速度直接起飞



# git 分支操作

git branch --merged                                       # 显示所有已合并到当前分支的分支

git branch --no-merged                                    # 显示所有未合并到当前分支的分支

git branch -m master master_copy                          # 本地分支改名

git checkout -b master_copy                               # 从当前分支创建新分支master_copy并检出

git checkout -b master master_copy                        # 上面的完整版

git checkout features/performance                         # 检出已存在的features/performance分支

git checkout --track hotfixes/BJVEP933                    # 检出远程分支hotfixes/BJVEP933并创建本地跟踪分支

git checkout v2.0                                         # 检出版本v2.0

git checkout -b devel origin/develop                      # 从远程分支develop创建新本地分支devel并检出

git checkout -- README                                    # 检出head版本的README文件（可用于修改错误回退）

git merge origin/master                                   # 合并远程master分支至当前分支

git cherry-pick ff44785404a8e                             # 合并提交ff44785404a8e的修改

git push origin master                                    # 将当前分支push到远程master分支

git push origin :hotfixes/BJVEP933                        # 删除远程仓库的hotfixes/BJVEP933分支



merge 分支点合并，有冲突时add+commit完成合并

cherry-pick 把目标提交拿到当前分支，只会合并提交的文件。目标提交未更改但和当前提交不同的文件不会改变

rebase 改变基底，和让提交记录混乱，不推荐。原理差不多是把另一条分支的节点一个一个的合并到新的分支



# git stash

默认情况下，`git stash`会缓存下列文件：

- 添加到暂存区的修改（staged changes）
- Git跟踪的但并未添加到暂存区的修改（unstaged changes）

但不会缓存一下文件：

- 在工作目录中新的文件（untracked files）
- 被忽略的文件（ignored files）

`git stash`命令提供了参数用于缓存上面两种类型的文件。使用`-u`或者`--include-untracked`可以stash untracked文件。使用`-a`或者`--all`命令可以stash当前目录下的所有修改。

```shell
git stash

git stash save # 能指定名字

git stash pop # 使用并删除序号最前面的

git stash apply # 使用但不删除(可指定序号)

git stash list   

git stash drop

git stash clear

git stash show [-p]/[--patch]
```

举例：

```shell
D:\tem\test-reposity>git stash save 15
Saved working directory and index state On master: 15

D:\tem\test-reposity>git stash list
stash@{0}: On master: 15

D:\tem\test-reposity>git stash 
Saved working directory and index state WIP on master: 4bbfa0f 13

# 后加入的反而序号靠前
D:\tem\test-reposity>git stash list
stash@{0}: WIP on master: 4bbfa0f 13
stash@{1}: On master: 15
```







