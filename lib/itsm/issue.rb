require "ntlm/http"
require "savon"
require "itsm/errors"

module ITSM
  class Issue < Struct.new(:key, :number, :summary, :url, :assigned_to_email, :assigned_to_user)
    
    
    def self.open
      http = Net::HTTP.start("ecphhelper", 80)
      req = Net::HTTP::Get.new("/ITSM.asmx/GetOpenCallsEmergingProducts")
      req.ntlm_auth("Houston", "cph.pri", "gKfub6mFy9BHDs6")
      response = http.request(req)
      parse_issues(response.body).map do |issue|
        self.new(
          issue["SupportCallID"],
          issue["CallNumber"],
          issue["Summary"],
          href_of(issue["CallDetailLink"]),
          issue["AssignedToEmailAddress"].try(:downcase))
      end
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
