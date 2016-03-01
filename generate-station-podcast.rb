require 'faraday'
require 'feedjira'
require 'rss'
require 'json'

class Station
  attr_accessor :items
  attr_accessor :playlist
end

class Show
  attr_accessor :name
  attr_accessor :format
  attr_accessor :podcast_url
  attr_accessor :teaser
  attr_accessor :website
end

station = Station.new
items = Array.new
playlist = Array.new

station.items = items
station.playlist = playlist

raw = Faraday.get("https://spreadsheets.google.com/feeds/cells/1V8eNrK7kSNPf3tfgcVBl8pm4xwHoyV_c2SOQLDLY8M0/od6/public/values?alt=json").body
data = JSON.parse(raw)

shows = Array.new
show = Show.new

data["feed"]["entry"].each_with_index do |e, index|
  column = e["gs$cell"]["col"].to_i

  case column
  when 1
    show.name = e["content"]["$t"]
  when 2
    show.format = e["content"]["$t"]
  when 3
    show.podcast_url = e["content"]["$t"]
  when 4
    show.teaser = e["content"]["$t"]
  when 5
    show.website = e["content"]["$t"]
  end

  if column == 5
    shows << show
    show = Show.new
  end

end

shows.each do |show|
  connection = Faraday.new show.podcast_url do |conn|
    conn.use FaradayMiddleware::FollowRedirects
    conn.adapter Faraday.default_adapter
  end

  xml = connection.get.body
  feed = Feedjira::Feed.parse_with Feedjira::Parser::ITunesRSS, xml

  if show.format == "SERIAL"
    feed.entries.reverse!
  end

  feed.entries[0].title = "#{show.name} - #{show.teaser}"
  feed.entries[0].summary = feed.description
  feed.entries[0].url = show.website
  items << feed.entries[0]
end

station.playlist = station.items.sort_by { |item| item.published}.reverse!

rss = RSS::Maker.make("2.0") do |maker|

  channel = maker.channel
  channel.title = "Spotlight from RadioPublic."
  channel.description = "Listen to previews and trailers for podcasts and radio shows."
  channel.link = "http://www.radiopublic.com/spotlight.xml"
  channel.language = "en-us"
  channel.copyright = "Copyright #{Date.today.year}"
  channel.lastBuildDate = "#{Date.today}"

  image = maker.image
  image.url = "http://www.example.com/images/app_rss_logo.jpg"
  image.title = "Spotlight from RadioPublic."

  channel.itunes_author = "Matt MacDonald"
  channel.itunes_owner.itunes_name = "RadioPublic"
  channel.itunes_owner.itunes_email='spotlight@radiopublic.com'

  channel.itunes_keywords = %w(trailers previews snippets shows)

  channel.itunes_subtitle = "Highlighting great podcasts and radio shows."
  channel.itunes_summary = "Spotlight from RadioPublic highlights podcasts and shows that we think you'd like."

  # below is what iTunes uses for your "album art", different from RSS standard
  channel.itunes_image = "/path/to/logo.png"
  channel.itunes_explicit = "No"

  category = channel.itunes_categories.new_category
  category.text = "Arts"
  category.new_category.text = "Literature"

  station.playlist[0..50].each do |entry|
    maker.items.new_item do |item|
      item.link = entry.enclosure_url
      item.title = entry.title
      link = entry.url
      item.link = link
      item.itunes_keywords = entry.itunes_keywords
      item.guid.content = link
      item.guid.isPermaLink = true
      item.pubDate = entry.published

      item.description = entry.summary
      item.itunes_summary = entry.summary
      item.itunes_subtitle = entry.title
      item.itunes_explicit = "Yes"
      item.itunes_author = entry.author
      item.updated = entry.published

      item.enclosure.url = entry.enclosure_url
      item.enclosure.length = entry.enclosure_length
      item.enclosure.type = entry.enclosure_type
    end
  end
end

puts rss.to_s
