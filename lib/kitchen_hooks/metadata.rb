module KitchenHooks
  # General information about the project
  SUMMARY  = %q.GitLab WebHoook for automated Chef Server uploads.
  AUTHOR   = 'Sean Clemmer'
  EMAIL    = 'sclemmer@bluejeans.com'
  LICENSE  = 'ISC'
  HOMEPAGE = 'https://github.com/sczizzo/kitchen-hooks'

  # Project root
  ROOT = File.dirname(__FILE__), '..', '..'

  # Pull the project version out of the VERSION file
  VERSION = File.read(File.join(ROOT, 'VERSION')).strip

  # Every project deserves its own ASCII art
  ART = <<-'EOART'
           _ _       _                                  _
      /\ /(_) |_ ___| |__   ___ _ __   /\  /\___   ___ | | _____
     / //_/ | __/ __| '_ \ / _ \ '_ \ / /_/ / _ \ / _ \| |/ / __|
    / __ \| | || (__| | | |  __/ | | / __  / (_) | (_) |   <\__ \
    \/  \/|_|\__\___|_| |_|\___|_| |_\/ /_/ \___/ \___/|_|\_\___/
  EOART
end