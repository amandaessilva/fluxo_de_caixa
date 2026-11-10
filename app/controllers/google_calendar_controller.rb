class GoogleCalendarController < ApplicationController
  OAUTH_STATE_TTL = 15.minutes
  MAX_PENDING_OAUTH_STATES = 5

  def connect
    unless GoogleCalendarApi.configured?
      return redirect_to settings_path, alert: 'Configure GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET e GOOGLE_REDIRECT_URI antes de conectar o Google Calendar.'
    end

    expected_origin = URI.parse(ENV.fetch('GOOGLE_REDIRECT_URI'))
    current_origin = URI.parse(request.base_url)
    unless same_origin?(current_origin, expected_origin)
      expected = origin_label(expected_origin)
      current = origin_label(current_origin)
      return redirect_to settings_path, alert: "Abra o app pelo mesmo endereço configurado no callback OAuth. Endereço atual: #{current}; callback: #{expected}."
    end

    state = SecureRandom.hex(32)
    session.delete(:google_calendar_oauth_state)
    states = active_oauth_states
    states << { 'value' => state, 'issued_at' => Time.current.to_i }
    session[:google_calendar_oauth_states] = states.last(MAX_PENDING_OAUTH_STATES)
    redirect_to GoogleCalendarApi.new(current_user).authorization_url(state: state), allow_other_host: true
  rescue URI::InvalidURIError
    redirect_to settings_path, alert: 'GOOGLE_REDIRECT_URI não é um endereço válido. Confira a configuração OAuth do servidor.'
  end

  def callback
    unless consume_oauth_state(params[:state].to_s)
      return redirect_to settings_path, alert: 'A sessão OAuth não corresponde ao retorno. Inicie uma nova tentativa usando o mesmo endereço do app e sem reutilizar uma autorização anterior.'
    end
    return redirect_to settings_path, alert: 'A conexão com o Google Calendar foi cancelada.' if params[:error].present?
    return redirect_to settings_path, alert: 'O Google não retornou a autorização necessária.' if params[:code].blank?

    api = GoogleCalendarApi.new(current_user)
    tokens = api.exchange_code!(params[:code])
    unless tokens['refresh_token'].present? || current_user.google_refresh_token.present?
      current_user.update!(google_access_token_ciphertext: nil, google_access_token_expires_at: nil)
      return redirect_to settings_path, alert: 'O Google não concedeu acesso persistente. Remova o acesso do app nas configurações da sua Conta Google e conecte novamente.'
    end

    api.ensure_calendar!
    GoogleCalendarEntrySync.sync_all
    current_user.update!(google_calendar_sync_error: nil)
    redirect_to settings_path, notice: 'Google Calendar conectado. As despesas planejadas foram sincronizadas no calendário Pagamentos.'
  rescue GoogleCalendarApi::Error, ActiveRecord::RecordInvalid => error
    current_user.update_column(:google_calendar_sync_error, 'A conexão ou sincronização falhou. Verifique as credenciais do Google e tente sincronizar novamente.') if current_user&.persisted?
    redirect_to settings_path, alert: "Não foi possível conectar ao Google Calendar: #{error.message}"
  end

  def sync
    return redirect_to settings_path, alert: 'Conecte o Google Calendar primeiro.' unless current_user.google_calendar_connected?

    GoogleCalendarEntrySync.sync_all
    current_user.update!(google_calendar_sync_error: nil)
    redirect_to settings_path, notice: 'Despesas planejadas sincronizadas com o Google Calendar.'
  rescue GoogleCalendarApi::Error => error
    current_user.update_column(:google_calendar_sync_error, 'A sincronização falhou. Verifique a conexão com o Google e tente novamente.')
    redirect_to settings_path, alert: "Não foi possível sincronizar: #{error.message}"
  end

  def disconnect
    return redirect_to settings_path, notice: 'O Google Calendar já está desconectado.' unless current_user.google_calendar_connected?

    api = GoogleCalendarApi.new(current_user)
    api.clear_app_events!
    api.revoke!
    current_user.update!(google_refresh_token_ciphertext: nil, google_access_token_ciphertext: nil,
                         google_access_token_expires_at: nil,
                         google_calendar_sync_error: nil)
    redirect_to settings_path, notice: 'Google Calendar desconectado. Os eventos do calendário Pagamentos foram removidos.'
  rescue GoogleCalendarApi::Error => error
    redirect_to settings_path, alert: "Não foi possível desconectar com segurança: #{error.message}"
  end

  private

  def same_origin?(left, right)
    left.scheme&.downcase == right.scheme&.downcase &&
      left.host&.downcase == right.host&.downcase &&
      left.port == right.port
  end

  def origin_label(uri)
    default_port = uri.scheme == 'https' ? 443 : 80
    port = uri.port == default_port ? '' : ":#{uri.port}"
    "#{uri.scheme}://#{uri.host}#{port}"
  end

  def active_oauth_states
    cutoff = OAUTH_STATE_TTL.ago.to_i
    Array(session[:google_calendar_oauth_states]).select do |item|
      item.is_a?(Hash) && item['value'].is_a?(String) && item['issued_at'].to_i >= cutoff
    end
  end

  def consume_oauth_state(returned_state)
    states = active_oauth_states
    matched = states.find do |item|
      stored_state = item['value']
      returned_state.present? && stored_state.bytesize == returned_state.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(stored_state, returned_state)
    end
    session[:google_calendar_oauth_states] = matched ? states.reject { |item| item['value'] == matched['value'] } : states
    matched.present?
  end
end
