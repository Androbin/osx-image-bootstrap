#!/bin/bash

if [[ `id -u` -eq 0 ]]; then
	echo "Try again, not as root."
	exit 1
fi


IOS_VERSIONS="8.1,8.2,8.3,8.4,9.0,9.1,9.2,9.3,10.0,10.1,10.2,10.3"
declare -a RUBIES=('2.3.3' '2.4.1')
DEFAULT_RUBY="2.4.1"
declare -a GEMS=('nomad-cli' 'cocoapods' 'bundler' 'rake' 'xcpretty' 'fastlane')
declare -a BREW_PKGS=('git' 'wget' 'mercurial' 'xctool' 'node' \
  'coreutils' 'postgresql' 'postgis' 'sqlite' 'go' 'gpg' 'carthage' \
  'md5deep' 'pyenv' 'tmate' 'cmake' 'swiftlint' 'maven')
declare -a BREW_CASK_PKGS=('java' 'oclint' 'rubymotion' 'xquartz')
declare -a PIP_PKGS=('virtualenv' 'numpy' 'scipy' 'tox')
declare -a NODE_VERSIONS=('6' '5' '4' '0.12' '0.10' '0.8' 'iojs')
export NVM_VERSION="v0.33.2"
export RVM_VERSION="1.29.2"

TRAVIS_SSH_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDEe8yPui0lLZpgaRNghw1H/2SGrpWV7Frw5FkftKGvMjkCL/FP6FeNZOUfWk5qISlhgkjZPu78nioZrUndTjOnSS8pWbecTrQCLKijufOS7A4n212bsdLpMwNuUE8lI1T0i9GcMRYfyK2jm/mosJkED2MomVzBi45NkEjG9IK/OncDcw+i15PDZcwONKZujc04KfNevhCIEt1sGJ0/mffwmQW5KVeKl5RjkKBxlmjo4ZSEVJV0CfzFQaua3c3cSswl3i5RX1wP6ciGfJlI/OZlXdQO4AwtcNFumklJFa2wf6BbRzXsaAieBnc1O2z885rEpXeeOsNzI/z6A+jLwEte2jZgMDh2x5fN3b4Au/iZt7ZhD7241QxN2quz3ej1zjr9MDJizQyzCrOvjvdNWE6CyAjoyF7aYptHCXuSjUbe7i+xx1PQk/MA+lEWAAzW+N4v4nSkHhVcyHnCzZB1WOlmSDNh19CvpF7zwnzs95D25goAH/veImF3RUMzKT5VTETqDgzF1CneAPq16//cIE/fnxtej0e5ZVPbj7oAgPEt0ERIgUo852iLjCHhD2n4juV564yGhs4Gf8eu3aGV+6kzzt8jBZlsiATF1WIwXJQy9Ga8F36v/GZmWVv+NIyRVw0aW1n8xaUzpVBdiNR8u+LvpOX9St6B4Z1iB6m0nhV2Sw== travis@mac"

macos_system_prefs_setup() {
  echo "--- setting system preferences."
  sudo systemsetup -settimezone GMT
  sudo systemsetup -setsleep Off
  sudo systemsetup -setcomputersleep Off
  sudo systemsetup -setdisplaysleep Off
  sudo systemsetup -setharddisksleep Off
  sudo systemsetup -setremotelogin on
  defaults write NSGlobalDomain NSAppSleepDisabled -bool YES
}

travis_ssh_key_setup() {
  if [[ ! -d ~/.ssh ]]; then
    echo "--- make .ssh/ && set permissions."
    mkdir -p ~/.ssh
    chmod 0700 ~/.ssh
  fi

  echo "--- Add Travis SSH key to authorized_keys && set permissions."
  echo "$TRAVIS_SSH_KEY" > ~/.ssh/authorized_keys
  chmod 0600 ~/.ssh/authorized_keys
}

passwordless_sudo_setup() {
  if [[ ! -f /etc/sudoers.d/travis ]]; then
    echo "--- Enable passwordless sudo for travis"
    echo 'travis ALL = (ALL) NOPASSWD:ALL' | sudo tee -a /etc/sudoers.d/travis
    sudo chmod 600 /etc/sudoers.d/travis
  else
    echo "--- passwordless sudo is enabled. Skipping."
  fi
}

harden_sshd_config() {
  echo "--- Putting hardened sshd config in place"
  sudo tee /etc/ssh/sshd_config <<EOF
# generated by travis
SyslogFacility AUTHPRIV
LogLevel VERBOSE
PubkeyAuthentication yes
AuthorizedKeysFile	.ssh/authorized_keys
PasswordAuthentication no
KbdInteractiveAuthentication no
KerberosAuthentication no
ChallengeResponseAuthentication no
GSSAPIAuthentication no
UsePAM no
UseDNS no
PermitEmptyPasswords no
LoginGraceTime 1m
PermitRootLogin no
UsePrivilegeSeparation sandbox
Subsystem sftp /usr/libexec/sftp-server
EOF

}

dot_bashrc_setup() {

  echo "--- Overwrite .bashrc with our own."
  cat > ~/.bashrc <<EOF
# generated by travis
export LC_ALL="en_US.UTF-8"
export LANG="en_US.UTF-8"
export TRAVIS=true
export CI=true
EOF
}

dot_profile_setup() {
  echo "--- Ensure that ~/.profile loads ~/.bashrc"
  cat > ~/.profile <<EOF
# generated by travis
[[ -s "\$HOME/.bashrc" ]] && source "\$HOME/.bashrc"
EOF
}

dot_bash_profile_setup() {
  echo "--- Ensure that ~/.bash_profile contents are correct"
  cat > ~/.bash_profile <<EOF
# generated by travis

# load .profile
[[ -s "\$HOME/.profile" ]] && source "\$HOME/.profile"

# help nvm work
export NVM_DIR="\$HOME/.nvm"
[[ -s "\$NVM_DIR/nvm.sh" ]] && source "\$NVM_DIR/nvm.sh"

# help rvm work
[[ -s "\$HOME/.rvm/scripts/rvm" ]] && source "\$HOME/.rvm/scripts/rvm"
export PATH="\$PATH:$HOME/.rvm/bin"
EOF
  # we want what we've written to take effect before we do more work
  source ~/.bash_profile
}

gemrc_setup() {
  if [[ ! $(grep no-document ~/.gemrc) ]]; then
    echo "--- add 'gem: --no-document' so gem installs don't include documentation"
    cat > ~/.gemrc <<EOF
gem: --no-document
EOF
  else
    echo "--- .gemrc is good. Skipping."
  fi
}

disable_scheduled_software_updates() {
  if [[ ! $(sudo softwareupdate --schedule | grep off) ]]; then
    echo "--- Turn off automatic software updating"
    sudo softwareupdate --schedule off
  else
    echo "--- Automatic software updates are disabled. Skipping."
  fi
}

brew_setup_update() {
  echo "--- Install/upgrade brew."
  brew upgrade || ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install) </dev/null"

  echo "--- Update installed packages"
  brew update
}

brew_packages_install() {
  echo "--- Install tools with brew"
  for PKG in "${BREW_PKGS[@]}"; do
    if [[ ! $(brew list | grep $PKG) ]]; then
      brew install $PKG
    else
     echo "$PKG present"
    fi
  done

  echo "--- Cleaning up after brew"
  brew cleanup
}

brew_cask_setup_update() {
  echo "--- Install brew-cask"
  brew tap caskroom/cask

  echo "--- Update installed casks"
  brew tap buo/cask-upgrade # needed to update casks
  brew cu --all --yes
}

brew_cask_packages_install() {
  echo "--- Install tools with brew-cask"
  for PKG in "${BREW_CASK_PKGS[@]}"; do
    if [[ ! $(brew cask list | grep $PKG) ]]; then
      brew cask install $PKG
    else
     echo "$PKG present"
    fi
  done

  echo "--- Cleaning up after brew-cask"
  brew cask cleanup
}

rubymotion_update() {
  echo "--- Update RubyMotion"
  # To prevent RubyMotion permission errors because `sudo motion update` created
  # this
  mkdir -p ~/Library/RubyMotion
  sudo motion update
}

python_libraries_install() {
  echo "--- Checking Python Libraries."
  # pip installs should be idempotent.
  for PKG in "${PIP_PKGS[@]}"; do
    if [[ ! $(pip show $PKG) ]]; then
        echo "--- Installing $PKG"
        pip install $PKG
    elif [[ $(pip list --format=legacy --outdated | grep -v latest | grep $PKG) ]]; then
        echo "--- Upgrading $PKG"
        pip install $PKG --upgrade
    fi
  done
}
nvm_install() {
  # nvm

  if [[ ! -d $HOME/.nvm ]]; then
    echo "--- Install nvm"
    wget -qO- "https://raw.githubusercontent.com/creationix/nvm/$NVM_VERSION/install.sh" | bash
  else
    echo "--- nvm present. Skipping."
  fi
}

node_versions_install() {
  source $HOME/.nvm/nvm.sh

  # for now we just call install each time, so that already
  # installed versions also get updated.
  for VER in "${NODE_VERSIONS[@]}"; do
    nvm install $VER
  done
}

rvm_install() {
  rvm_common() {
    echo "rvm_silence_path_mismatch_check_flag=1" > ~/.rvmrc
    echo "--- Some rvm cleanup."
    rvm cleanup all
  }

  if [[ ! -d $HOME/.rvm ]]; then
    echo "--- Installing rvm."
    command curl -sSL https://rvm.io/mpapis.asc | gpg2 --import -
    curl -sSL https://get.rvm.io | bash -s stable
    rvm_common
  else
    export RVM_REMOTE_VERSION="$(curl  https://raw.githubusercontent.com/rvm/rvm/master/VERSION)"
    if [[ $RVM_REMOTE_VERSION != $RVM_VERSION ]]; then
      echo "--- Updating rvm."
      rvm get stable
      rvm_common
    else
      echo "--- rvm up to date. Skipping."
    fi
  fi
  source "$HOME/.rvm/scripts/rvm" # needed for future rvm usage in this script
}

rubies_install() {
  echo "--- Install rubies with rvm"
  for RUBY in "${RUBIES[@]}"; do
    if [[ ! $(rvm list | grep $RUBY) ]]; then
      rvm install $RUBY
    else
      echo "--- ruby version $RUBY is present. Skipping."
    fi
  done

  rvm alias create default $DEFAULT_RUBY
}

common_rubygems_install() {
  # 'do' is 'quoted' because otherwise vim syntax highlighting is v unhappy
  echo "--- Install gems for all rubies"

  for G in "${GEMS[@]}"; do
    for R in $(rvm list strings|grep 'ruby'); do
      if [[ $(gem list '^'$G'$') ]]; then
        echo "--- $G already installed. Skipping."
      else
        echo "--- Installing $G"
        rvm $R do gem install $G
      fi
    done
  done

  echo "--- Upgrading existing gems."
  rvm all 'do' gem update
  rvm all 'do' gem cleanup
}

cocoapods_setup() {
  echo "--- Updating Cocoapods."
  pod setup | wc -l
}

set_env_travisci_true() {
  echo '--- set $CI, $TRAVIS to true'
  sudo tee /etc/launchd.conf <<EOF
setenv CI true
setenv TRAVIS true
EOF
}

setup_travis_runner() {
  cat > ~/runner.rb <<EOF
#!/usr/bin/env ruby

require "pty"
require "socket"

server = TCPServer.new("127.0.0.1", 15782)
socket = server.accept

PTY.spawn("/usr/bin/env", "TERM=xterm", "/bin/bash", "--login", "/Users/travis/build.sh") do |stdout, stdin, pid|
  IO.copy_stream(stdout, socket)

  _, exit_status = Process.wait2(pid)
  File.open("/Users/travis/build.sh.exit", "w") { |f| f.print((exit_status.exitstatus || 127).to_s) }
end

socket.close
EOF

  chmod +x ~/runner.rb

  mkdir -p ~/Library/LaunchAgents
  if [[ -f ~/Library/LaunchAgents/com.travis-ci.runner.plist ]]; then
    sudo chown travis ~/Library/LaunchAgents/com.travis-ci.runner.plist
  fi

  cat > ~/Library/LaunchAgents/com.travis-ci.runner.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.travis-ci.runner</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/travis/runner.rb</string>
    </array>
    <key>StandardOutPath</key>
    <string>/Users/travis/runner.rb.out</string>
    <key>StandardErrorPath</key>
    <string>/Users/travis/runner.rb.err</string>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF
  sudo chown root ~/Library/LaunchAgents/com.travis-ci.runner.plist
  # needed because of newer security restrictions
  sudo launchctl load ~/Library/LaunchAgents/com.travis-ci.runner.plist
}

xcode_simulator_reset() {
  echo " --- Create simulator devices with fastlane snapshot"
  fastlane snapshot reset_simulators --force --ios_version $IOS_VERSIONS
}

system_info() {
  echo " --- Create /usr/local/travis"
  sudo mkdir -p /usr/local/travis
  sudo chown -R travis /usr/local/travis

  echo " --- Set up system-info"
  git clone https://github.com/travis-ci/system-info.git
  cd system-info
  git reset --hard v2.0.3
  rvm use ruby-2.3.3 # some of the pinned dependencies don't work on 2.4.x
  bundle install
  bundle exec system-info report \
    --formats human,json \
    --human-output /usr/local/travis/system_info \
    --json-output /usr/local/travis/system_info.json
  cd ..
  rm -rf system-info
  rvm use default
}

software_updates() {
  echo "You may want to install the following:"
  sudo softwareupdate -l -a
  echo "You can do so using 'sudo softwareupdate -i -a'"
}

bootstrap() {
  echo "--- Let's bootstrap this macOS"

  echo "--- Some of what we'll be installing:"
  echo "--- * Rubies: ${RUBIES[@]}"
  echo "--- * brew pkgs: ${BREW_PKGS[@]}"
  echo "--- * brew-cask pkgs: ${BREW_CASK_PKGS[@]}"
  echo "--- * node versions: ${NODE_VERSIONS[@]}"
  echo "--- * nvm version: ${NVM_VERSION[@]}"
  echo "--- * rvm version: ${RVM_VERSION[@]}"

  macos_system_prefs_setup
  travis_ssh_key_setup
  passwordless_sudo_setup
  harden_sshd_config
  dot_bashrc_setup
  dot_profile_setup
  dot_bash_profile_setup
  gemrc_setup
  disable_scheduled_software_updates
  brew_setup_update
  brew_packages_install
  rubymotion_update
  python_libraries_install
  nvm_install
  node_versions_install
  rvm_install
  rubies_install
  cocoapods_setup
  set_env_travisci_true
  setup_travis_runner
  ###xcode_simulator_reset #fastlane isn't working with xcode 9 yet
  software_updates

  if [[ ! $(find /usr/local/travis/* -cmin -50) ]]; then
    system_info
  else
    echo "--- system_info updated recently. Skipping."
  fi
}

# Check for Xcode, otherwise bootstrap things
xcodebuild -version > /dev/null && bootstrap || echo "You need to install Xcode" && exit 1
