require 'bundler'
Bundler.require(:default)
require 'action_view'
require 'socket'
require 'yaml'

# Recursively symbolize keys
def symbolize_keys(hash)
  hash.keys.each do |key|
    new_key = (key.to_sym rescue key) || key
    hash[new_key] = hash.delete(key)
    if hash[new_key].is_a? Hash
      symbolize_keys(hash[new_key])
    end
  end
end

# Load the configuration.
config_file = 'gist_notifier.yml'
if ARGV[0]
  if File.exists?(ARGV[0])
    config_file = ARGV[0]
  else
    $stderr.puts "'#{ARGV[0]}' does not exist, defaulting to '#{config_file}'"
  end
end
config = YAML.load(File.read(config_file))

# Symbolize the keys in the config hash.
symbolize_keys(config)

# Default configuration
config = {
  gist_notifier: {
    always_use_id: false
  }
}.merge(config)

# Flag for determining whether to send email notifications on first run with
# this database.
fresh_database = false
unless File.exists?(config[:db][:file])
  fresh_database = true
end

# Open the database and create its structure if necessary.
db = SQLite3::Database.new(config[:db][:file])
db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS comments (
    comment_id int,
    gist_id int
  );
SQL

# Create a client instance to GitHub.
client = Octokit::Client.new(
  access_token: config[:github][:access_token]
)

# Retrieve Gists.
gists = client.user.rels[:gists].get
loop do # Keep looping until we run out of pages.
  gists.data.each do |gist|
    # Pull the known comments about this gist.
    known_comments = db.execute(
      'SELECT comment_id FROM comments WHERE gist_id = ?',
      [gist.id]
    ).map { |e| e[0] }

    # Request the comments if there are more comments than what we know about
    # already.
    if gist.comments > known_comments.length
      comments = gist.rels[:comments].get.data
      comments.each do |comment|
        # Skip known comments.
        next if known_comments.include?(comment.id)

        # Store this comment's reference.
        db.execute(
          'INSERT INTO comments VALUES(?, ?)',
          [comment.id, gist.id]
        )

        # Don't notify about comments on the first run of a new database.
        next if fresh_database

        # Don't notify about our comments.
        next if comment.user.login == client.login

        # Determine the appropriate display name for the Gist.
        gist_name = "gist:#{gist.id}"
        unless config[:gist_notifier][:always_use_id]
          gist_first_filename = gist.files.fields.first.to_s
          unless gist_first_filename.start_with?('gistfile')
            gist_name = gist_first_filename
          end
        end

        html_body = <<-EOF
          #{ActionView::Base.new.simple_format(comment.body)}
          <p style="font-size:small;-webkit-text-size-adjust:none;color:#666;">
            &mdash;<br>Reply to this on
            <a href='https://gist.github.com/#{gist.owner.login}/#{gist.id}#comment-#{comment.id}'>GitHub Gist</a>.<br>
            This was sent by
            <a href="https://github.com/kramerc/gist_notifier">Gist Notifier</a>
            from host #{Socket.gethostname}. This is not an official GitHub email.
          </p>
        EOF

        Pony.mail(config[:mail].merge(
          subject: "Re: [Gist] #{gist_name}",
          html_body: html_body
        ))
      end
    end
  end

  # Break out of the loop if there are no more pages.
  break if gists.rels[:next].nil?

  # Another page, go to the next relation and loop.
  gists = gists.rels[:next].get
end
