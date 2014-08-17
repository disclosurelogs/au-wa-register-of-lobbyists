require 'scraperwiki'
require 'yaml'
require 'openssl'
class Array
  def to_yaml_style
    :inline
  end
end
require 'net/https'
require 'uri'

html = ""
uri = URI.parse("https://www.lobbyists.wa.gov.au")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true if uri.scheme == "https"  # enable SSL/TLS
http.verify_mode = OpenSSL::SSL::VERIFY_NONE
http.start {
  http.request_get("/Pages/WhoIsOnTheRegister.aspx") {|res|
    html = res.body
  }
}

# resume from the last incomplete url if the scraper was terminated
resumeFromHere = false
last_url = ScraperWiki.get_var("last_url", "")
if last_url == "" or last_url.length < 3 then resumeFromHere = true end

# Next we use Nokogiri to extract the values from the HTML source.

require 'nokogiri'
page = Nokogiri::HTML(html)
urls = page.css('#MSOZoneCell_WebPartWPQ3 table').search('a').map {|a| a.attributes['href']}
lobbyists = urls.map do |url|
  if url == last_url and resumeFromHere == false
    resumeFromHere = true
  end

  if resumeFromHere
    ScraperWiki.save_var("last_url", url.to_s)
    puts "Downloading #{url}" 
    begin
      lobbyhtml = ""
      http.start {
        http.request_get("/Pages/#{url}") {|res|
          lobbyhtml = res.body
        }
      }
      lobbypage = Nokogiri::HTML(lobbyhtml)
  
      #thanks http://ponderer.org/download/xpath/ and http://www.zvon.org/xxl/XPathTutorial/Output/
      employees = []
      clients = []
      owners = []
      names = []
      lobbyist_firm = {}
  
      companyABN=lobbypage.xpath("//b[text() = 'A.B.N:']/ancestor::th/following-sibling::node()/text()")
      companyName=lobbypage.xpath("//b[text() = 'Name:']/ancestor::th/following-sibling::node()/text()").first
      lobbyist_firm["business_name"] = companyName.to_s
      lobbyist_firm["trading_name"] = companyName.to_s
      lobbyist_firm["abn"] =  companyABN.to_s
      lobbypage.xpath("//b[text() = 'Owner Details']/ancestor::tr/following-sibling::node()//td/text()").each do |owner|
        ownerName = owner.content.gsub(/\u00a0/, '').strip
        if ownerName.empty? == false and ownerName.class != 'binary'
            owners << { "lobbyist_firm_name" => lobbyist_firm["business_name"],"lobbyist_firm_abn" => lobbyist_firm["abn"], "name" => ownerName }
            names << ownerName 
        end
      end
      lobbypage.xpath("//b[text() = 'Client Details']/ancestor::tr/following-sibling::node()//td/text()").each do |client|
        clientName = client.content.gsub(/\u00a0/, '').strip
        if clientName.empty? == false and clientName.class != 'binary' and not names.include?(clientName)
            clients << { "lobbyist_firm_name" => lobbyist_firm["business_name"],"lobbyist_firm_abn" => lobbyist_firm["abn"], "name" => clientName }
        end
      end
      lobbypage.xpath("//b[text() = 'Lobbyist Details']/ancestor::tr/following-sibling::node()//td/text()").each do |employee|
        employeeName = employee.content.gsub(/\u00a0/, '').gsub("  ", " ").strip
        if employeeName.empty? == false and employeeName.class != 'binary' and not names.include?(employeeName)
            employees << { "lobbyist_firm_name" => lobbyist_firm["business_name"],"lobbyist_firm_abn" => lobbyist_firm["abn"], "name" => employeeName}
        end
      end 
      lobbyist_firm["last_updated"] = lobbypage.xpath("//b[text() = 'Details Last Updated: ']/ancestor::p/text()").to_s

     ScraperWiki.save(unique_keys=["name","lobbyist_firm_abn"],data=employees, table_name="lobbyists")
     ScraperWiki.save(unique_keys=["name","lobbyist_firm_abn"],data=clients, table_name="lobbyist_clients")
     ScraperWiki.save(unique_keys=["name","lobbyist_firm_abn"],data=owners, table_name="lobbyist_firm_owners")
     ScraperWiki.save(unique_keys=["business_name","abn"],data=lobbyist_firm, table_name="lobbyist_firms")
    rescue Timeout::Error => e
      print "Timeout on #{url}"
    end
  else
    puts "Skipping #{url}"    
  end
end
ScraperWiki.save_var("last_url", "")
