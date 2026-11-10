require 'net/http'
require 'uri'
require 'json'

class GoogleCalendarApi
  API_ROOT = 'https://www.googleapis.com/calendar/v3'.freeze
  TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token'.freeze
  SCOPE = 'https://www.googleapis.com/auth/calendar.app.created'.freeze

  class Error < StandardError; end

  def self.configured?
    ENV['GOOGLE_CLIENT_ID'].present? && ENV['GOOGLE_CLIENT_SECRET'].present? && ENV['GOOGLE_REDIRECT_URI'].present?
  end

  def initialize(user)
    @user = user
  end

  def authorization_url(state:)
    query = {
      client_id: ENV.fetch('GOOGLE_CLIENT_ID'),
      redirect_uri: ENV.fetch('GOOGLE_REDIRECT_URI'),
      response_type: 'code',
      scope: SCOPE,
      access_type: 'offline',
      prompt: 'consent',
      include_granted_scopes: 'true',
      state: state
    }
    "https://accounts.google.com/o/oauth2/v2/auth?#{URI.encode_www_form(query)}"
  end

  def exchange_code!(code)
    data = post_form(TOKEN_ENDPOINT, {
      code: code,
      client_id: ENV.fetch('GOOGLE_CLIENT_ID'),
      client_secret: ENV.fetch('GOOGLE_CLIENT_SECRET'),
      redirect_uri: ENV.fetch('GOOGLE_REDIRECT_URI'),
      grant_type: 'authorization_code'
    })
    save_tokens!(data)
    data
  end

  def ensure_calendar!
    return @user.google_calendar_id if @user.google_calendar_id.present?

    data = request(:post, 'calendars', body: { summary: 'Pagamentos', timeZone: 'America/Sao_Paulo' })
    @user.update!(google_calendar_id: data.fetch('id'))
    data.fetch('id')
  end

  def get_event(event_id)
    request(:get, event_path(event_id), allow_not_found: true)
  end

  def upsert_event(event_id, attributes)
    attributes = attributes.merge(id: event_id)
    if get_event(event_id)
      request(:put, event_path(event_id), body: attributes)
    else
      request(:post, "calendars/#{calendar_id}/events", body: attributes)
    end
  rescue Error => error
    raise unless error.message.include?('409')

    request(:put, event_path(event_id), body: attributes)
  end

  def delete_event(event_id)
    request(:delete, event_path(event_id), allow_not_found: true)
  end

  def each_app_event
    page_token = nil
    loop do
      query = { maxResults: 2500, privateExtendedProperty: 'app=fluxo_de_caixa' }
      query[:pageToken] = page_token if page_token.present?
      data = request(:get, "calendars/#{ERB::Util.url_encode(calendar_id)}/events?#{URI.encode_www_form(query)}")
      Array(data['items']).each { |event| yield event }
      page_token = data['nextPageToken']
      break if page_token.blank?
    end
  end

  def clear_app_events!
    each_app_event { |event| delete_event(event.fetch('id')) }
  end

  def revoke!
    return if @user.google_refresh_token.blank?

    post_form('https://oauth2.googleapis.com/revoke', { token: @user.google_refresh_token })
  end

  private

  def calendar_id
    @user.google_calendar_id.presence || ensure_calendar!
  end

  def event_path(event_id)
    "calendars/#{ERB::Util.url_encode(calendar_id)}/events/#{ERB::Util.url_encode(event_id)}"
  end

  def access_token
    return @user.google_access_token if @user.google_access_token.present? && @user.google_access_token_expires_at&.future?

    data = post_form(TOKEN_ENDPOINT, {
      client_id: ENV.fetch('GOOGLE_CLIENT_ID'),
      client_secret: ENV.fetch('GOOGLE_CLIENT_SECRET'),
      refresh_token: @user.google_refresh_token,
      grant_type: 'refresh_token'
    })
    save_tokens!(data)
    @user.google_access_token
  end

  def save_tokens!(data)
    attributes = {}
    attributes[:google_access_token] = data['access_token'] if data['access_token'].present?
    attributes[:google_refresh_token] = data['refresh_token'] if data['refresh_token'].present?
    attributes[:google_access_token_expires_at] = Time.current + data.fetch('expires_in', 3600).to_i.seconds - 60.seconds
    @user.update!(attributes)
  end

  def post_form(url, fields)
    uri = URI(url)
    request = Net::HTTP::Post.new(uri)
    request.set_form_data(fields)
    response = perform_http(uri, request)
    parse_response(response)
  end

  def request(method, path, body: nil, allow_not_found: false)
    uri = URI("#{API_ROOT}/#{path}")
    klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put, delete: Net::HTTP::Delete }.fetch(method)
    http_request = klass.new(uri)
    http_request['Authorization'] = "Bearer #{access_token}"
    http_request['Content-Type'] = 'application/json'
    http_request.body = JSON.generate(body) if body
    response = perform_http(uri, http_request)
    return nil if allow_not_found && response.code.to_i == 404
    return true if method == :delete && response.code.to_i == 204

    parse_response(response)
  end

  def perform_http(uri, request)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 8, read_timeout: 20) do |http|
      http.request(request)
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => error
    raise Error, "Google Calendar indisponível: #{error.class}"
  end

  def parse_response(response)
    return {} if response.body.blank?

    data = JSON.parse(response.body)
    return data if response.code.to_i.between?(200, 299)

    detail = case data
             when Hash
               api_error = data['error']
               if api_error.is_a?(Hash)
                 api_error['message'].presence || api_error['status'].presence
               else
                 data['error_description'].presence || api_error.presence
               end
             when String
               data.presence
             end
    detail ||= "HTTP #{response.code}"
    raise Error, "Google Calendar respondeu #{response.code}: #{detail}"
  rescue JSON::ParserError
    raise Error, "Resposta inválida do Google Calendar (#{response.code})."
  end
end
