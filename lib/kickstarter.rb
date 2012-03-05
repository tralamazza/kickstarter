require "rubygems"
require "nokogiri"
require "em-http-request"
require "kickstarter/version"
require "kickstarter/project"

module Kickstarter
  BASE_URL = "http://www.kickstarter.com"

  Type = {
    :recommended => 'recommended', 
    :popular     => 'popular', 
    :successful  => 'successful',
    :most_funded => 'most-funded'
  }
  
  Lists = {
    :recommended       => "recommended",
    :popular           => "popular",
    :recently_launched => "recently-launched",
    :ending_soon       => "ending-soon",
    :small_projects    => "small-projects",
    :most_funded       => "most-funded",
    :curated           => "curated-pages",
    :successful        => 'successful'
  }

  # Kickstarter.categories |name, url_path_name|
  #   puts name
  # end
  def self.categories(&block)
    EM.run do
      http = EM::HttpRequest.new(BASE_URL).get
      http.errback { EM.stop }
      http.callback do
        Nokogiri::HTML(http.response).css("h5 + ul.list-footer-categories, h5 + ul + ul").each do |node|
          node.css("a").each do |node_cat|
            block.call(node_cat.text, node_cat["href"].match(/discover\/categories\/(.*)\?/)[1])
          end
        end # Nokogiri::HTML
        EM.stop
      end # http.callback
    end # EM.run
  end

  # by category
  # /discover/categories/:category/:subcategories 
  #  :type # => [recommended, popular, successful, most_funded]
  def self.by_category(category, options = {}, &block)
    path = File.join(BASE_URL, 'discover/categories', category, Type[options[:type] || :popular])
    list_projects(path, options, &block)
  end

  # by lists
  # /discover/:list
  def self.by_list(list, options = {}, &block)
    path = File.join(BASE_URL, 'discover', Lists[list.to_sym])
    list_projects(path, options, &block)
  end
  
  private

  def self.list_projects(url, options = {}, &block)
    start_page = options.fetch(:page, 1)

    EM.run do
      http = EM::HttpRequest.new("#{url}?page=#{start_page}").get
      http.errback { EM.stop }
      http.callback do
        doc = Nokogiri::HTML(http.response)
        nodes = doc.css('.project')
        if nodes.empty?
          EM.stop
          return
        end
        nodes.each { |node| block.call( Kickstarter::Project.new(node) ) }

        start_page += 1 # skip the one we just read
        pages = options.fetch(:pages, :all)
        if pages == :all
          end_page = doc.css(".pagination a:nth-last-of-type(2)").text.to_i
        elsif
          end_page = start_page + pages - 2
        end
        EM.stop if start_page > end_page

        processed = 0 # counter
        # create one request per page
        multi = (start_page .. end_page).map { |p|
          EM::HttpRequest.new("#{url}?page=#{p}").get
        }
        multi.each do |multi_http|
          multi_http.errback do
            processed += 1
            EM.stop if processed == multi.length
          end
          multi_http.callback do
            nodes = Nokogiri::HTML(multi_http.response).css('.project')
            nodes.each { |node| block.call(Kickstarter::Project.new(node)) }
            processed += 1
            EM.stop if processed == multi.length
          end
        end # multi.each do |multi_http|

      end # http.callback
    end # EM.run do
  end

end
