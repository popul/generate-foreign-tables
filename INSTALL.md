# Setup for program to run

This program requires Ruby 2 environement and Bundler. The basic
setup to run the program is as follows.

* Install Ruby 2.2 & Bundler per Platform
* ``bundle install``
* ``bundle exec generate_foreign_tables.rb``

## Mac OS X

On Mac using brew is the easiest but any preferred system to install Ruby
will work.

* [Install brew](http://brew.sh/)
* ``brew install ruby22``
* ``gem install bundler``
* You may need to modify your PATH as directed by Ruby or Brew
* ``bundle install --path vendor/bundle``
* ``bundle exec generate_foreign_tables.rb``

## Linux 

* ``apt-get install ruby ``
* ``apt-get install bundler``
* ``bundle install --path vendor/bundle``
* ``bundle exec generate_foreign_tables.rb``

