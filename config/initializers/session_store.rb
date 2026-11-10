Rails.application.config.session_store :cookie_store, key: '_fluxo_session', same_site: :lax, httponly: true, secure: Rails.env.production?
