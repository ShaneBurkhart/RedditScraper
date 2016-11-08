require "csv"
require "json"
require "open-uri"

SUBREDDITS = [
    "/r/learnprogramming",
]
KEYWORDS = [
    /([^.]html|\^html)/i,
    /([^.]css|\^css)/i,
    /javascript/i,
]

# Amount of time to go back before scraping listings. Be reasonable.
# days * hours * mins * seconds
TIME_AGO = 4 * 24 * 60 * 60
# Amount of time to scrape back once TIME_AGO has been reached.
# days * hours * mins * seconds
TIME_RANGE = 2 * 24 * 60 * 60
# Amount of time between requests to Reddit in seconds
REQUEST_DELAY = 4


REDDIT_URL = "https://www.reddit.com"
# Get this at the beginning so it doesn't change throughout execution.
NOW = Time.now.utc.to_i
# The time we start scraping at when searching back in time.
START_TIME = NOW - TIME_AGO
# The time we finish scraping at when searching back in time.
END_TIME = START_TIME - TIME_RANGE

# Permalinks of reddit posts.
listings_to_scrape = []
# The keywords we found when searching subreddits.
keywords_found = []

def new_listings_url(subreddit, after)
    url = "#{REDDIT_URL}#{subreddit}/new.json"

    if after then
        return "#{url}?after=#{after}"
    end

    return url
end

def has_keywords?(text, keywords)
    text ||= ""
    keywords ||= []

    text = text

    keywords.each do |keyword|
        if text.match(keyword) then
            return true
        end
    end

    return false
end

def search_comment(comment, keywords_found)
    comment_data = comment["data"]
    replies = comment_data["replies"]
    body = comment_data["body"]
    author = comment_data["author"]
    subreddit = comment_data["subreddit"]

    if has_keywords?(body, KEYWORDS) then
        keywords_found.push({
            type: "comment",
            author: author,
            text: body,
            subreddit: subreddit,
        })
    end

    return if !replies.kind_of?(Array)

    reply_comments = replies["data"]["children"]

    reply_comments.each do |c|
        search_comment(c, keywords_found)
    end
end

# Find the listings to scrape
SUBREDDITS.each do |subreddit|
    puts subreddit
    done = false
    after_id = nil

    while !done do
        listings_url = new_listings_url(subreddit, after_id)

        # Keep running the url until it works.
        while true do
            begin
                puts listings_url
                raw_listings_data = open(listings_url).read
                break
            rescue StandardError => e
                puts e
                sleep(REQUEST_DELAY)
            end
        end

        listings_data = JSON.parse(raw_listings_data)["data"]

        listings = listings_data["children"]
        after_id = listings_data["after"]

        listings.each do |listing|
            listing_data = listing["data"]
            url = listing_data["permalink"]
            created_at = listing_data["created_utc"]

            if created_at <= START_TIME then
                listings_to_scrape.push(url)

                # If past the start time and end time, then break.
                if created_at <= END_TIME then
                    done = true
                    break
                end
            end
        end

        sleep(REQUEST_DELAY)
    end
end

puts "Found #{listings_to_scrape.count} listings"

# Search listing and comments for keyword.
listings_to_scrape.each do |listing_url, i|
    puts "#{i + 1} of #{listings_to_scrape.count}"
    url = "#{REDDIT_URL}#{listing_url}.json"
    next if !url.ascii_only?

    # Keep running the url until it works.
    while true do
        begin
            puts url
            raw_data = open(url).read
            break
        rescue StandardError => e
            puts e
            sleep(REQUEST_DELAY)
        end
    end

    data = JSON.parse(raw_data)
    listing_data = data[0]["data"]["children"][0]["data"]
    comments_data = data[1]["data"]
    comments = comments_data["children"]

    title = listing_data["title"]
    text = listing_data["selftext"]
    author = listing_data["author"]
    subreddit = listing_data["subreddit"]

    if has_keywords?(title, KEYWORDS) or has_keywords?(text, KEYWORDS) then
        # type, author, text, subreddit_id
        keywords_found.push({
            type: "post",
            author: author,
            text: "#{title}\n\n#{text}",
            subreddit: subreddit,
        })
    end

    comments.each do |comment|
        search_comment(comment, keywords_found)
    end

    sleep(REQUEST_DELAY)
end

CSV.open("#{NOW.to_i}_reddit.csv", "wb") do |csv|
    keywords_found.each do |k|
        csv << [k[:type], k[:subreddit], k[:author], k[:text]]
    end
end
