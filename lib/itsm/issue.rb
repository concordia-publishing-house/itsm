require "ntlm/http"
require "savon"
require "itsm/errors"

module ITSM
  class Issue < Struct.new(:key, :number, :summary, :url, :assigned_to_email, :notes, :opened_by)
    
    
    def self.open
      http = Net::HTTP.start("ecphhelper", 80)
      req = Net::HTTP::Get.new("/ITSM.asmx/GetOpenCallsEmergingProducts")
      req.ntlm_auth("Houston", "cph.pri", "gKfub6mFy9BHDs6")
      response = http.request(req)
      parse_issues(response.body).map do |issue|
        self.new(
          issue["SupportCallID"],
          issue["CallNumber"].to_i,
          issue["Summary"],
          href_of(issue["CallDetailLink"]),
          issue["AssignedToEmailAddress"].try(:downcase),
          issue["Notes"].to_s,
          issue["OpenedByUser"])
      end
    end
    
    def self.find(number)
      number = number.to_i
      open.find { |issue| issue.number == number }
    end
    
    
    
    def self.create(options={})
      username = options.fetch :username
      summary = options.fetch :summary
      notes = options.fetch :notes
      
      # http://savonrb.com/version2/client.html
      client = Savon.client(wsdl: "http://itsmweb/WebService.asmx?wsdl")
      response = client.call(:submit_incident, message: {userName: username, summary: summary, notes: notes})
      unless response.body[:submit_incident_response][:submit_incident_result][:success]
        raise ITSM::Error, response.body[:submit_incident_response][:submit_incident_result][:return_message]
      end
      issue_id = response.body[:submit_incident_response][:submit_incident_result][:support_call_id]
      client.call(:assign_to_queue, message: {supportCallID: issue_id, queueName: "Emerging Products"})
      "http://ecphhelper/Design/ViewITSMCallDetails.aspx?SupportCallID=#{issue_id}"
    end
    
    
    
    def close!
      http = Net::HTTP.start("ecphhelper", 80)
      req = Net::HTTP::Post.new("/ITSM.asmx/CloseCall", {"Content-Type" => "application/x-www-form-urlencoded"})
      req.body = "supportCallID=#{key}"
      req.ntlm_auth("Houston", "cph.pri", "gKfub6mFy9BHDs6")
      response = http.request(req)
      
      response = Hash.from_xml(response.body)
      unless response.fetch("GenericReturn", {})["Success"] == "true"
        raise ITSM::Error, response.fetch("GenericReturn", {})["ReturnMessage"]
      end
    end
    
    def assign_to!(username)
      username = username.username if username.respond_to? :username
      
      http = Net::HTTP.start("ecphhelper", 80)
      req = Net::HTTP::Post.new("/ITSM.asmx/AssignCall", {"Content-Type" => "application/x-www-form-urlencoded"})
      req.body = "supportCallID=#{key}&userOrQueueName=#{username}"
      req.ntlm_auth("Houston", "cph.pri", "gKfub6mFy9BHDs6")
      response = http.request(req)
      
      response = Hash.from_xml(response.body)
      unless response.fetch("GenericReturn", {})["Success"] == "true"
        raise ITSM::Error, response.fetch("GenericReturn", {})["ReturnMessage"]
      end
    end
    
    
  private
    
    def self.parse_issues(xml)
      Array.wrap(
        Hash.from_xml(xml)
          .fetch("ArrayOfOpenCallData", {})
          .fetch("OpenCallData", []))
    rescue REXML::ParseException # malformed response upstream
      Rails.logger.error "\e[31;1m#{$!.class}\e[0;31m: #{$!.message}"
      []
    end
    
    def self.href_of(link)
      Nokogiri::HTML::fragment(link).children.first[:href]
    end
    
  end
end
