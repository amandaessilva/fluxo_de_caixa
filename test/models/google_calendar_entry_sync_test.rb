require 'test_helper'
require 'time'

class GoogleCalendarEntrySyncTest < ActiveSupport::TestCase
  Response = Struct.new(:body, :code)

  class FakeGoogleCalendarApi
    attr_reader :events, :deleted_ids

    def initialize
      @events = {}
      @deleted_ids = []
    end

    def ensure_calendar! = 'calendar-id'
    def get_event(id) = events[id]
    def upsert_event(id, attributes) = events[id] = attributes

    def delete_event(id)
      deleted_ids << id
      events.delete(id)
    end
  end

  setup do
    setup_finances
    @entry = entry(date: Date.current + 10.days, status: 'planned')
    @user = User.create!(email: 'calendar@example.com', password: 'senha-sintetica-segura')
    @user.update!(google_calendar_id: 'calendar-id', google_refresh_token: 'refresh-token')
    @api = FakeGoogleCalendarApi.new
  end

  test 'despesa planejada cria evento de dia inteiro e avisos diários três dias antes às 13h e 19h' do
    with_fake_api { GoogleCalendarEntrySync.call(@entry.id) }

    payment = @api.events.fetch(GoogleCalendarEntrySync.pending_event_id(@entry.id))
    assert_equal({ date: @entry.date.iso8601 }, payment[:start])
    assert_equal ['RRULE:FREQ=DAILY'], payment[:recurrence]
    assert_equal 'transparent', payment[:transparency]

    reminder_13 = @api.events.fetch(GoogleCalendarEntrySync.reminder_13_event_id(@entry.id))
    reminder_19 = @api.events.fetch(GoogleCalendarEntrySync.reminder_19_event_id(@entry.id))
    assert_equal (@entry.date - 3.days).iso8601, Time.iso8601(reminder_13[:start][:dateTime]).to_date.iso8601
    assert_equal 13, Time.iso8601(reminder_13[:start][:dateTime]).hour
    assert_equal 19, Time.iso8601(reminder_19[:start][:dateTime]).hour
    assert_equal ['RRULE:FREQ=DAILY'], reminder_13[:recurrence]
    assert_equal ['RRULE:FREQ=DAILY'], reminder_19[:recurrence]
  end

  test 'benefício utilizado não gera tarefa ou avisos de pagamento' do
    benefit = entry(kind: 'benefit_used', status: 'planned', date: Date.current + 5.days)

    with_fake_api { GoogleCalendarEntrySync.call(benefit.id) }

    assert_empty @api.events
  end

  test 'marcar uma despesa como realizada encerra avisos e registra o evento como pago' do
    with_fake_api do
      GoogleCalendarEntrySync.call(@entry.id)
      @entry.update!(status: 'actual')
    end

    assert_equal Date.current, @entry.reload.completed_on
    refute @api.events.key?(GoogleCalendarEntrySync.pending_event_id(@entry.id))
    refute @api.events.key?(GoogleCalendarEntrySync.reminder_13_event_id(@entry.id))
    refute @api.events.key?(GoogleCalendarEntrySync.reminder_19_event_id(@entry.id))
    paid = @api.events.fetch(GoogleCalendarEntrySync.paid_event_id(@entry.id))
    assert_equal "Pago · #{@entry.description}", paid[:summary]
    assert_equal Date.current.iso8601, paid[:start][:date]
  end

  test 'tokens Google são armazenados criptografados' do
    refute_equal 'refresh-token', @user.reload.google_refresh_token_ciphertext
    assert_equal 'refresh-token', @user.google_refresh_token
    assert @user.google_calendar_connected?
  end

  test 'parser apresenta erros OAuth em JSON string ou no formato error_description' do
    api = GoogleCalendarApi.new(@user)
    plain_string_error = assert_raises(GoogleCalendarApi::Error) do
      api.send(:parse_response, Response.new('"invalid_grant"', '400'))
    end
    assert_includes plain_string_error.message, 'invalid_grant'

    oauth_error = assert_raises(GoogleCalendarApi::Error) do
      api.send(:parse_response, Response.new('{"error":"invalid_grant","error_description":"Refresh token revoked"}', '400'))
    end
    assert_includes oauth_error.message, 'Refresh token revoked'
  end

  test 'parser mantém mensagens estruturadas de erro da Calendar API' do
    api = GoogleCalendarApi.new(@user)
    error = assert_raises(GoogleCalendarApi::Error) do
      api.send(:parse_response, Response.new('{"error":{"code":403,"message":"Insufficient Permission"}}', '403'))
    end
    assert_includes error.message, 'Insufficient Permission'
  end

  private

  def with_fake_api(&block)
    GoogleCalendarEntrySync.with_api_factory(->(_user) { @api }, &block)
  end
end
