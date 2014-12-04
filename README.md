# Kitchen Hooks

GitLab WebHoook for automated Chef Server uploads following Kitchen standards.

## Changelog

### 1.1

* Started checking in `Gemfile.lock` for future reference
* Added `port` and `environment` options to `kitchen_hooks server`
* Move `rake fpm` `.deb` artifacts under `pkg` alongside `.gem` files
* Commits to the Kitchen trigger data bag, role, and environment uploads
* Tagging a cookbook with a version triggers a cookbook upload (frozen)
* Tagging a realm with the name of an environment applies version constraints

### 1.0

* Initial release. Gem structure in place, but lacking functionaily