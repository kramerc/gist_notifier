# Gist Notifier

An interim notifier that sends emails about new comments left on your own gists on [GitHub Gist](https://gist.github.com/).

## Why?

GitHub Gist hasn't been notifying about new comments or mentions for quite some time and it is a known issue as [stated on a community repository](https://github.com/isaacs/github/issues/21).
As I don't regularly check my gists for new comments and rely on notifications, I created this notifier for the interim.

Gist Notifier does not and is unable to notify about mentions to you left in comments. As mentions could be left anywhere and not just your own gists, doing so would require going through every gist on GitHub and checking the comments of each one, which is unfeasible to do.

## Installation

The steps given here assume you have Git, Ruby, Bundler, and SQLite3 installed. You will need a C compiler (or [DevKit](http://rubyinstaller.org/add-ons/devkit/)) in order to install the [sqlite3 gem](https://rubygems.org/gems/sqlite3).

1. Clone the repository.

  ```bash
  git clone git://github.com/kramerc/gist_notifier.git
  ```

2. Create an access token at https://github.com/settings/applications

3. Create `gist_notifier.yml` with the following template and configure your access token and email settings. It is possible to have multiple configuration by passing a path as an argument to the Ruby script.

  ```yaml
  db:
    # Database for caching comment IDs so duplicate notifications aren't sent.
    file: gist_notifier.db
  github:
    # Create an access token at https://github.com/settings/applications
    access_token: accesstokenfromgithub
  mail:
    # These options mimic Pony's mail options.
    # See https://github.com/benprew/pony#transport
    from: Gist Notifier <gistnotifier@example.com>
    to: me@example.com
    via: smtp
    via_options:
      address: smtp.example.com
      port: 587
      user_name: gistnotifier@example.com
      password: abc123
      authentication: plain
  ```

4. Run Bundler to install the script's dependencies.

  ```bash
  bundle install
  ```

5. Run Gist Notifier for the first time. This will create the database and build the cache. You won't be notified about comments on the first run with a new database.

  ```bash
  bundle exec ruby gist_notifier.rb
  ```

6. Set up Gist Notifier to run at regular intervals as appropriate using your system's scheduler, such as cron. GitHub does [rate limits](http://developer.github.com/v3/#rate-limiting) API requests so you will not want to run this script too often otherwise you may burn out the requests you can make for the hour.

  An example crontab entry that runs the notifier every 15 minutes:

  ```
  */15 * * * * cd /path/to/gist_notifier && bundle exec ruby gist_notifier.rb
  ```

## Requests usage

The amount of requests Gist Notifier will use depends on how many gists you have on your account and how often your gists receive new comments. Currently, the API will pull 30 gists per page and Gist Notifier will have to go through each page. That means for each 30 gists you have on your account you can expect Gist Notifier to at minimum use that many requests of the rounded up amount of the number of gists divided by 30.

Gist Notifier will then request any gist that has a higher comment count than the amount the notifier is already aware of.

##### To break it down

* Each 30 gists equals 1 request.

  ```ruby
  # An example to demonstrate the logic.
  gist_count = 45
  (gist_count / 30.0).ceil # Minimum amount of requests
  #=> 2
    ```

* For each gist on the page, if the amount of comments is greater than the amount of cached comment IDs in the database, then a request is made to load that gist.

  ```ruby
  known_comments = db.execute(
    'SELECT comment_id FROM comments WHERE gist_id = ?',
    [gist.id]
  ).map { |e| e[0] }
  if gist.comments > known_comments.length
    # Request the gist and go through the comments
  end
  ```
