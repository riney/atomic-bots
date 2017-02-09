require 'active_support/core_ext/date'
require 'json'
require 'pg'
require 'slack-ruby-bot'

class LunchBot < SlackRubyBot::Bot
  SlackRubyBot::Client.logger.level = Logger::INFO

  SlackRubyBot.configure do |config|
    config.send_gifs = false
  end

  @@last_updated = nil
  @@times_used = 0
  @@db = nil

  ICONMAP = {
    "http://legacy.cafebonappetit.com/assets/cor_icons/menu-item-type-43c4b7.png?v=1456809068": "S",
    "http://legacy.cafebonappetit.com/assets/cor_icons/menu-item-type-d58f59.png?v=1456809068": "FF",
    "http://legacy.cafebonappetit.com/assets/cor_icons/menu-item-type-668e3c.png?v=1456809068": "VG",
    "http://legacy.cafebonappetit.com/assets/cor_icons/menu-item-type-ce9d00.png?v=1456809068": "↓G",
    "http://legacy.cafebonappetit.com/assets/cor_icons/menu-item-type-c9d18b.png?v=1456809068": "V"
  }

  command "menu", "What's for lunch?", "what's for lunch?", "what's for lunch", "What's for lunch" do |client, data, match|
    @@times_used += 1

    if needs_refresh?
      client.say(text: "Let me fetch the latest menu...", channel: data.channel)
      refresh_menu
    end

    if @@today.saturday? || @@today.sunday?
      client.say(text: "It's the weekend! No cafeteria food today.", channel: data.channel)
    else
      client.say(text: describe_menu(@@menu), channel: data.channel)
    end
  end

  command "legend" do |client, data, match|
    response = %{ *FF* Farm to Fork
*↓G* Made without gluten ingredients (not necessarily gluten free)
*V* Vegetarian
*VG* Vegan
*S* Seafood Watch }

    client.say(text: response, channel: data.channel)
  end

  command "status" do |client, data, match|
    response = "Last refreshed menu at #{@@last_updated || "never"}\n"
    response += "Accessed #{@@times_used} times since startup."

    client.say(text: response, channel: data.channel)
  end

  help do
    title "Lunch Bot"
    desc "Lunch is my life."

    command "menu" do
      desc "Tells you what's on the cafeteria menu today."
    end

    command "What's for lunch?" do
      desc "Same thing."
    end

    command "status" do
      desc "Tells you the last time the menu was updated."
    end

    command "legend" do
      desc "Tells you the meaning of the various item attributes (FF, VG, etc.)"
    end
  end

  def self.refresh_menu
    @@menu = []
    @@last_updated = DateTime.now
    scraped_menu = JSON.parse Net::HTTP.get_response(URI.parse ENV["EXTRACTOR_URL"]).body
    if (scraped_menu['code'] == 1001)
      SlackRubyBot::Client.logger.info "We've exceeded the maximum number of requests for the month. Sorry."
    else
      items = scraped_menu['extractorData']['data'][0]['group']
      @@menu = items.collect do |item|
        {
          name: item['Item'].first['text'],
          price: item['Price'].first['text'],
          description: item['Description'].first['text'],
          attributes: (item['Attributes'] || {}).collect { |attr| ICONMAP[attr['src'].to_sym] }.join(", ")
        }
      end
      SlackRubyBot::Client.logger.info "Refreshed menu - got #{@@menu.size} items."
    end
  end

  def self.needs_refresh?
    @@today = DateTime.now
    @@last_updated.nil? || (@@today >= @@last_updated.midnight.tomorrow) && !@@today.saturday? && !@@today.sunday?
  end

  def self.describe_menu(menu)
    if menu.empty?
      response = "I'm sorry, I'm having trouble getting the menu today. Try again later, or visit the LDAC cafeteria web page at http://public-ldac.cafebonappetit.com/"
    else
      response = "Today's menu for #{@@last_updated.strftime('%A, %d %b %Y')}\n\n"
      menu.each do |item|
        response << "*#{item[:name]}*#{item[:attributes].empty?? "" : " (" + item[:attributes] + ")"} #{item[:price]}\n_#{item[:description]}_\n\n"
      end
    end

    response
  end

  def self.connect_db
    SlackRubyBot::Client.logger.info "Connecting to db #{ENV['DATABASE_URL']}"
    begin
      @@db = PG::Connection.open(dbname: ENV['DATABASE_URL'])
    rescue PG::Error
      SlackRubyBot::Client.logger.error "Couldn't connect: #{$!}"
    end
    SlackRubyBot::Client.logger.info "Connected to db #{ENV['DATABASE_URL']}"
  end
end

SlackRubyBot::Client.logger.info "Lunchbot commencing operations."
LunchBot.refresh_menu
LunchBot.run
