#!/usr/bin/env ruby

require 'twitter'
require 'shellwords'
require 'open-uri'
require 'yaml'
require 'optparse'

yaml_config = YAML.load_file(File.join(File.expand_path(File.dirname(__FILE__)), "config.yaml"))

@client = Twitter::REST::Client.new do |config|
  config.consumer_key        = yaml_config["consumer_key"]
  config.consumer_secret     = yaml_config["consumer_secret"]
  config.access_token        = yaml_config["access_token"]
  config.access_token_secret = yaml_config["access_token_secret"]
end

def get_favorite_tweets(user)

  params = { "count" => 10, "screen_name" => user, "include_entities" => true }
  tweet_obj = @client.favorites(params)

  tweets = []
  tweet_obj.each { |tweet|
    parse_tweet(tweet)
    @client.unfavorite(tweet.id)
  }
end

def parse_tweet(tweet)

    # Blockquote the tweet text
    markdown_tweet = "#{tweet.text.gsub(/^/, '> ')}\n\n"
    # Include tweet place if available (with a little map pin)
    markdown_tweet << "> &#x1f4cd; _#{tweet.place.full_name}_\n\n" if tweet.place?
    # Put the name of the person and their twitter name inside a <cite> tag with a link to the original tweet
    markdown_tweet << "<cite>--#{tweet.user.name} (@#{tweet.user.screen_name}) on [twitter](https://twitter.com/#{tweet.user.screen_name.downcase}/status/#{tweet.id})</cite>\n"

    # Expand URLs
    unless tweet.urls.empty?
      tweet.urls.each { |url|
        # Replace tweet URLs with expanded version and wrap in markdown link
        markdown_tweet.gsub!(/#{url.url}/,"[#{url.display_url}](#{url.expanded_url})")
      }
    end

    # Download first image from tweet
    image_path = nil
    unless tweet.media.empty?
      image_path = "/tmp/#{tweet.id}"
      tweet.media.each { |image|
        open(image.media_url) {|contents|
           File.open(image_path,"wb") do |file|
             file.puts contents.read
           end
        }
        # Replace tweet image urls with the expanded version and wrap in markdown link
        markdown_tweet.gsub!(/#{image.url}/,"[#{image.display_url}](#{image.media_url})")
        # WHAT?! break?! yes, for the day when Day One supports more then one image in a entry
        break
      }
    end

    # Try to find images hosted outside Twitter to download
    if image_path.nil?
      tweet.urls.each do |url|
        uri = URI.parse(url.expanded_url)
        if uri.host == "d.pr"
          uri.scheme = "https"
          munged_url = "#{uri}+"
        elsif uri.host == "cl.ly"
          munged_url = "#{uri}/download"
        elsif uri.host == "instagram.com"
          munged_url = "#{URI.join(uri, 'media/?size=l')}"
        else
          munged_url = uri
        end

        open(munged_url){ |contents|
          if contents.content_type.include?("image")
            image_path = "/tmp/#{tweet.id}"
            File.open(image_path,"wb") do |file|
              file.puts contents.read
            end
          end
        }
        break unless image_path.nil?
      end
    end

    puts markdown_tweet
    puts add_markdown_to_day_one(markdown_tweet, tweet.created_at, image_path) if @options.day_one
    File.delete(image_path) unless image_path.nil?
end

def add_markdown_to_day_one(markdown, datetime, image_path=nil)
  dayone_cmd = ["/usr/local/bin/dayone"]
  dayone_cmd << "-s=true"
  dayone_cmd << "-d=\"#{datetime}\""
  dayone_cmd << "-p=\"#{image_path}\"" unless image_path.nil?
  dayone_cmd << "new"
  puts dayone_cmd.join(" ")
  dayone_entry = `echo #{Shellwords.escape(markdown)} | #{dayone_cmd.join(" ")}`
  dayone_id = Regexp.new('\/([^/]*).doentry$',Regexp::IGNORECASE).match(dayone_entry)
  return dayone_id[1]
end

begin

  Options = Struct.new(:favorites, :url, :day_one)
  @options = Options.new
  @options.favorites = false
  @options.day_one = true

  optparse = OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on("-f", "--favorites", "Add a new Day One entry for each of #{yaml_config["twitter_username"]}'s favorited tweets") do |favorites|
      @options.favorites = favorites
    end
    opts.on("-u", "--url url", "Add a new Day One entry for the given tweet URL") do |url|
      @options.url = url.to_s
    end
    opts.on("--no-day-one", "Whether or not to output to Day One, default: true") do |no_day_one|
      @options.day_one = no_day_one
    end
  end
  optparse.parse!

  if !@options.favorites && @options.url.nil?
    puts "You must specify a url or use the --favorites flag to get favorited tweets.\n\n#{optparse}"
    exit 0
  end

  get_favorite_tweets(yaml_config["twitter_username"]) if @options.favorites

  unless @options.url.nil?
    status_id = /.+\/(\d+)\/?$/.match(@options.url)[1]
    parse_tweet(@client.status(status_id))
  end
end




