#PUPPET REPORT MODULE FOR COSCALE API
#
#Note that in puppet, all modules run in the same scope,
#so names can overlap and then problem ! 
#
# TO INSTALL :
# find out libdir
# $ puppet config print libdir
# /var/lib/puppet/lib
# create directory /puppet/reports/ in there
# $ sudo mkdir -p /var/lib/puppet/lib/puppet/reports
# put coscale.rb in there
# add report module to config /etc/puppet/puppet.conf
# example : 
# reports = store,coscale
#

require 'puppet'
require 'yaml'
require 'net/http'
require 'net/https'
require 'uri'
require 'json'

Puppet::Reports.register_report(:coscale) do

  desc "Send events to Coscale."


#The Coscale class
#All Coscale related functions go in here
  class Coscale

    #as a good programmer, we 'initialise' our variables
    @cs_accesstoken=''
    @cs_appid=''
    @cs_HTTPAuthorizationToken = '';

    #pass the necessary info on instantiation of the class
    def initialize(bu,at,ai)
      @cs_accesstoken = at
      @cs_appid = ai
      @cs_baseurl = bu + 'api/v1/app/' + ai + '/'
    end

    #login to api to get auth-token
    def _login(accesstoken, url)
      Puppet.debug "method = [" + __method__.to_s + "]"

      uri = URI.parse(url)

      data = "accessToken=" + accesstoken

#      Puppet.debug "uri = [" + uri.to_s + "]"
#      Puppet.debug "uri.host = [" + uri.host.to_s + "]"
#      Puppet.debug "uri.path = [" + uri.path.to_s + "]"
#      Puppet.debug "data = [" + data + "]"

      http = Net::HTTP.new(uri.host,443)
      http.use_ssl = true
      headers = {'Content-Type'=> 'application/x-www-form-urlencoded'}

      res, data = http.post(uri.path, data, headers)

#      Puppet.debug "res.code = [" + res.code.to_s + "," + res.message.to_s + "]"
#      Puppet.debug "res.body = [" + res.body.to_s + "]"

      if res.code != '200'
        raise ArgumentError, res.body
      end

      response = JSON.parse(res.body)
      token = response['token']

      Puppet.debug "token [#{token}] received."

      return token
    end



    #create the event on the API
    def _eventpush(name, url)
#      Puppet.debug "method = [" + __method__.to_s + "]"
      data = {'name'        => name,
              'description' => '',
              'type'        => '',
              'source'      => 'Puppet'}
      headers = {'HTTPAuthorization' => @cs_HTTPAuthorizationToken}

      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      if url.start_with?('https')
        http.use_ssl = true
      end

      request = Net::HTTP::Post.new(uri.request_uri, initheader = headers)
      request.set_form_data(data)
      res = http.request(request)

      if res.code == '409' || res.code == '200'
        response = JSON.parse(res.body)
          return nil, response["id"]
      end
      return res, nil
    end



    #set the data for the event on the API
    def _eventdatapush(message, timestamp, url)
#      Puppet.debug "method = [" + __method__.to_s + "]"

      data = {'message' => message,
              'timestamp' => timestamp,
              'subject' => 'subject',
              }

      headers = {'HTTPAuthorization' => @cs_HTTPAuthorizationToken}

      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      if url.start_with?('https')
        http.use_ssl = true
      end

      request = Net::HTTP::Post.new(uri.request_uri, initheader = headers)
      request.set_form_data(data)
      res = http.request(request)
      return res
    end



    #send an event to the API by :
    #checking if needed to login
    #sending the event
    #sending the event data
    def event(event_name, event_message, timestamp=0)
#      Puppet.debug "method = [" + __method__.to_s + "]"

      Puppet.debug "API EVENT - NME[" + event_name + "] MSG[" + event_message + "]"

#      Puppet.debug "AT=" + @cs_accesstoken
#      Puppet.debug "AI=" + @cs_appid
#      Puppet.debug "BU=" + @cs_baseurl

	if !@cs_HTTPAuthorizationToken
          @cs_HTTPAuthorizationToken = _login(@cs_accesstoken, @cs_baseurl + 'login/')
        end

        err, event_id = _eventpush(event_name, url=@cs_baseurl + 'events/')

        if err != nil
          if err.code == '401'
            @cs_HTTPAuthorizationToken = _login(@cs_accesstoken, @cs_baseurl + 'login/')
            err, event_id = _eventpush(name=event_name, url=@cs_baseurl + 'events/')
          end
          if !['401', nil].include? err.code
            Puppet.debug "Error : [" + err.body + "]"
            return
          end
        end

        url = @cs_baseurl + 'events/' + event_id.to_s + '/data/'

        err = _eventdatapush(event_message, timestamp, url=url)

        if err != nil
          if err.code == '401'
            @cs_HTTPAuthorizationToken = _login(@cs_accesstoken, @cs_baseurl + 'login/')
            err = _eventdatapush(event_message, timestamp, url=url)
          end 
          if err.code != '200'
            Puppet.debug "Error : [" + err.body + "]"
            return
          end
        end

    end	#of sub _event





  end	#of the class



  #the main procedure
  def process
    time1 = Time.new
    Puppet.debug "Coscale Module : " + time1.inspect

#    Puppet.debug "================================================"
#    Puppet.debug "raw summary = [" + raw_summary.to_s + "]"
#    Puppet.debug "================================================"
#    Puppet.debug "metrics = [" + metrics.to_s + "]"
#    Puppet.debug "================================================"
#    Puppet.debug "host= #{self.host}"
#    Puppet.debug "status= #{self.status}"
#    Puppet.debug "environment= #{self.environment}"
#    self.logs.each do |log|
#      Puppet.debug "================================================"
#      Puppet.debug "log.time = [" + log.time.to_s + "]"
#      Puppet.debug "log.level = [" + log.level.to_s + "]"
#      Puppet.debug "log.message = [" + log.message.to_s + "]"
#      Puppet.debug "log.source = [" + log.source.to_s + "]"
#    end
#    Puppet.debug "================================================"

    #first create a new instance of the class
    #and initialize it with the needed parameters
    cs = Coscale.new(
                       baseurl='https://api.coscale.com/',			#you can change this to test on production or so
                       accesstoken='32a5666e-2b5d-42db-a774-c11ba4646a4b',	#to be created in the API in users/accesstokens
                       appid='0017e2a5-0071-4320-bfcd-75239c2ecb75'		#to be extracted from the dashboard URL
                    )

    eventname = "Puppet Master - #{self.host}"					#this will show up as the event name

    self.logs.each do |log|			#loop through the reported events

      message = "[#{log.level.to_s}][#{log.message.to_s}][#{log.source.to_s}]"	#this will show up as the event message

      cs.event(
          event_name = eventname,              # Specify the required ``event_name`` parameter.
          event_message = message,             # Specify the required ``event_message`` parameter.
          timestamp = 0)                       # Specify the required ``event_timestamp`` parameter

    end


  end
end
