#!/usr/bin/env ruby
# -*- mode: ruby -*-
# vi: set ft=ruby :
Vagrant.configure('2') do |config|
  config.vm.provider :virtualbox do |vbox|
    vbox.customize [ 'modifyvm', :id, '--memory', 4096 ]
    vbox.customize [ 'modifyvm', :id, '--cpus', 4 ]
  end

  config.vm.define 'precise-test' do |node|
    node.vm.box = 'bento/ubuntu-12.04'
    node.vm.hostname = 'test'
    node.vm.network :private_network, ip: '10.10.10.10'
    node.vm.provision :shell, inline: <<-END
      set -x
      set -e
      RUBY_VERSION=2.2

      if ! hash ruby >/dev/null 2>&1 ; then
        apt-get update
        apt-get install -y make build-essential autoconf
        apt-get install -y vim htop curl git
        apt-get install -y libxml2-dev libxslt1-dev
        apt-get install -y software-properties-common python-software-properties
        apt-add-repository -y ppa:brightbox/ruby-ng
        apt-get update
        apt-get install -y "ruby${RUBY_VERSION}" "ruby${RUBY_VERSION}-dev"
        apt-get install -y ruby-switch
        ruby-switch --set "ruby${RUBY_VERSION}"
      fi

      dpkg -i /vagrant/tasks/package/artifacts/*.deb
      kitchen_hooks art
    END
  end

  config.vm.define 'trusty-test' do |node|
    node.vm.box = 'bento/ubuntu-14.04'
    node.vm.hostname = 'test'
    node.vm.network :private_network, ip: '10.10.10.11'
    node.vm.provision :shell, inline: <<-END
      set -x
      set -e
      RUBY_VERSION=2.2

      if ! hash ruby >/dev/null 2>&1 ; then
        apt-get update
        apt-get install -y make build-essential autoconf
        apt-get install -y vim htop curl git
        apt-get install -y libxml2-dev libxslt1-dev
        apt-get install -y software-properties-common
        apt-add-repository -y ppa:brightbox/ruby-ng
        apt-get update
        apt-get install -y "ruby${RUBY_VERSION}" "ruby${RUBY_VERSION}-dev"
        apt-get install -y ruby-switch
        ruby-switch --set "ruby${RUBY_VERSION}"
      fi

      dpkg -i /vagrant/tasks/package/artifacts/*.deb
      kitchen_hooks art
    END
  end
end