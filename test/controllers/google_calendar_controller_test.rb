require 'test_helper'
require 'uri'

class GoogleCalendarControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_finances
    sign_in
  end

  test 'recusa iniciar OAuth se o host aberto não corresponde ao callback configurado' do
    with_google_environment('http://localhost:3000/configuracoes/google-calendar/callback') do
      get connect_google_calendar_path

      assert_redirected_to settings_path
      follow_redirect!
      assert_includes response.body, 'Endereço atual'
    end
  end

  test 'mantém estados independentes para tentativas OAuth em abas diferentes' do
    with_google_environment('http://www.example.com/configuracoes/google-calendar/callback') do
      first_state = start_oauth_and_get_state
      second_state = start_oauth_and_get_state
      refute_equal first_state, second_state

      get google_calendar_callback_path, params: { state: first_state, error: 'access_denied' }
      assert_redirected_to settings_path
      follow_redirect!
      assert_includes response.body, 'foi cancelada'

      get google_calendar_callback_path, params: { state: second_state, error: 'access_denied' }
      assert_redirected_to settings_path
      follow_redirect!
      assert_includes response.body, 'foi cancelada'
    end
  end

  private

  def start_oauth_and_get_state
    get connect_google_calendar_path
    assert_response :redirect
    query = URI.decode_www_form(URI(response.location).query).to_h
    query.fetch('state')
  end

  def with_google_environment(redirect_uri)
    keys = %w[GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET GOOGLE_REDIRECT_URI]
    old_values = keys.to_h { |key| [key, ENV[key]] }
    ENV['GOOGLE_CLIENT_ID'] = 'test-client-id'
    ENV['GOOGLE_CLIENT_SECRET'] = 'test-client-secret'
    ENV['GOOGLE_REDIRECT_URI'] = redirect_uri
    yield
  ensure
    old_values&.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
  end
end
