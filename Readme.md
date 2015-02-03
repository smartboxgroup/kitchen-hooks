# Kitchen Hooks ![Version](https://img.shields.io/gem/v/kitchen_hooks.svg?style=flat-square)

The [Kitchen Hooks](http://git.bluejeansnet.com/kitchen-hooks) provide a GitLab
WebHoook for automated Chef Server uploads following Kitchen standards.


## What?

So [the Kitchen](http://wiki.bluejeansnet.com/operations/kitchen) is this thing
we have now in Operations to help guide cookbook development. The [Workflow](http://wiki.bluejeansnet.com/operations/kitchen#workflow)
sction of the docs prescribes how to go about your day in Chef land including
how to version, release, and deploy changes to a Chef server.

But that's only _one_ Chef server. What if we want redundancy?

A distributed/highly-available Chef would do the job. It comes in a few flavors:

1. Pay for whatever they're calling [Hosted Chef](https://manage.chef.io/signup) nowadays
2. Manually deploy a [highly-available setup in AWS](https://docs.getchef.com/install_server_ha_aws.html)
3. Manually deploy a [highly-available setup with DRBD](https://docs.getchef.com/server_high_availability.html#drbd)

The third option is basically a recipe for disaster. DRBD is known to lose data
in split-brain scenarios. So that's actually two flavors.

Hosted Chef seems like a great option. Until you start using it. They give you
whatever bleeding-edge version of Chef they're testing so you don't have time
to breathe between incompatible versions. Chef is notorious for yanking gems
and botching releases. They've also got some odd permissions you probably have
never seen before, because vanilla Chef server doesn't have organizations.

That leaves AWS as an option. But it's a lot of work, and weirdly completely
not automated.

All I care about is having my Chef data replicated, why does it have to be hard?
I mean, we've been using `git` hooks to fan out to Chef servers for years now!

### So let's do that.

The old post-receive hook was pretty basic, but it worked. By default, it would
look up the `knife` and `berks` configuration files (`.rb` and `.json`) in
`~/knives` then loop over them when uploading Chef objects found in the
checkout specified by the hook.

The new Kitchen Hooks works much the same, except we're using GitLab WebHooks
rather than traditional `git` hooks. This makes the Hooks easier to maintain,
as installing `git` hooks has not been automated, and WebHooks are opt-in.

The new Hooks cover three scenarios:

1. Pushes to the `master` branch of the Kitchen trigger an upload of all roles,
   environments, and data bags. This will overwrite any changes made on the Chef
   server, but you shouldn't be doing that anyway. Importantly, this has no
   effect on cookbook versions pinned in any environment.
2. Version tag pushes (e.g. `v1.0.0`) to cookbooks trigger a `knife`-style
   cookbook upload with `freeze` set to true. A `Berksfile.lock` will also
   trigger the equivalent of `berks install` and `berks upload`.
3. Environment tag pushes (e.g. `bjn_logger_prod`) to realm cookbooks trigger
   `berks apply` behavior. Remember to delete both the local and remote tags
   when you want to update an environment with a later version of the realm.

Actions performed by Kitchen Hooks are stored in a [Daybreak](http://propublica.github.io/daybreak/)
database and presented as a timeline in the [Web UI](http://git.bluejeansnet.com:4567).
Notifcations can are sent to HipChat.

## Installation

Try `gem install kitchen_hooks`. Or add it to your `Gemfile`. Or clone the repo
and `rake build`. Do all three, I don't care!


## Usage

After installing the gem, the `kitchen_hooks` executable should be available:

    $ kitchen_hooks help
    Commands:
    kitchen_hooks art             # Show application art
    kitchen_hooks help [COMMAND]  # Describe available commands or one specific command
    kitchen_hooks server          # Start application web server
    kitchen_hooks version         # Show application version

Use the `server` command to start the WebHook receiver:

    $ kitchen_hooks server -c etc/config.json -p 80 -e production
    == Sinatra/1.4.5 has taken the stage on 80 for production with backup from Thin
    Thin web server (v1.6.3 codename Protein Powder)
    Maximum connections set to 1024
    Listening on 0.0.0.0:80, CTRL+C to stop
    ...

## Configuration

The configuration file is just JSON. Hopefully it's obvious:

    {
      "hipchat": {
        "nick": "name",
        "room": "test",
        "token": "your_v1_api_token"
      },
      "knives": {
        "user": "~/.chef/knife.rb",
        "system": "/etc/chef/knife.rb",
        "another": "/path/to/knife.rb"
      }
    }

The `server` command also exposes some options for Sinatra configuration. See
`kitchen_hooks help server`.

## Development

### TODO

* Use Ridley for data bag, role, and environment uploads to remove Chef dependency

### Changelog

### 1.6

* Add requests to backlog for serial processing

#### 1.5

* Add release notifications
* Add indication of success or failure
* Only upload on commits to Kitchen `master` branch
* Add custom timeline icons to distinguish event types

#### 1.4

* Simplified configuration format (breaking!)
* Added support for HipChat notifications when configured
* Linked to tag name with `.../commits/TAG` where appropriate
* Replaced "modified" with more appropriate verb where appropriate
* Corrected `berks upload` functionality (`berks install` first)

#### 1.3

* Added local database to store history (Daybreak), visualized on homepage
* Added `database` option to `server` command
* Corrected GitLab link for tagged commits
* Process events in the background to avoid duplicate entries [INF-6040]

#### 1.2

* Added `bind` option to `server` command
* Added `berks upload` functionality when tagging realm versions

#### 1.1

* Moved `examples` to `etc`
* Started checking in `Gemfile.lock` for future reference
* Added `port` and `environment` options to `kitchen_hooks server`
* Move `rake fpm` `.deb` artifacts under `pkg` alongside `.gem` files
* Commits to the Kitchen trigger data bag, role, and environment uploads
* Tagging a cookbook with a version triggers a cookbook upload (frozen)
* Tagging a realm with the name of an environment applies version constraints

#### 1.0

* Initial release. Gem structure in place, but lacking functionaily