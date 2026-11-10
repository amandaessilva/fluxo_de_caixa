class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: [:new, :create]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: 'Muitas tentativas. Aguarde três minutos.' }
  def new; end
  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)
    if user&.authenticate(params[:password])
      reset_session
      session[:user_id] = user.id
      session[:expires_at] = 12.hours.from_now.to_i
      redirect_to root_path
    else
      flash.now[:alert] = 'E-mail ou senha inválidos.'
      render :new, status: :unprocessable_entity
    end
  end
  def destroy
    current_user.previews.destroy_all
    reset_session
    redirect_to new_session_path, status: :see_other
  end
end
