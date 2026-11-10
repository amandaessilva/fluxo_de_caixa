class ApplicationController < ActionController::Base
  before_action :require_authentication
  helper_method :current_user, :selected_year, :selected_month, :selected_status

  private
  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:expires_at].to_i > Time.current.to_i
  end
  def require_authentication
    response.headers['Cache-Control'] = 'no-store'
    redirect_to new_session_path unless current_user
  end
  def selected_year
    @selected_year ||= FinancialYear.find_by(year: params[:year]) || FinancialYear.find_by(year: session[:year]) || FinancialYear.order(year: :desc).first
  end
  def require_year
    if selected_year
      session[:year] = selected_year.year
    else
      redirect_to settings_path, notice: 'Crie seu primeiro ano financeiro para começar.'
    end
  end
  def selected_month = params[:month].to_i.in?(1..12) ? params[:month].to_i : Date.current.month
  def selected_status = Entry::STATUSES.key?(params[:status]) ? params[:status] : 'actual'
  def money_param(value)
    str = value.to_s.strip.gsub(/[[:space:]R$]/, '')
    str = str.delete('.').tr(',', '.') if str.include?(',')
    number = BigDecimal(str)
    raise ArgumentError, 'Use um valor com até duas casas decimais.' unless number.finite? && (number * 100).frac.zero?
    number
  rescue ArgumentError
    raise ArgumentError, 'Informe um valor válido, por exemplo 1250,90.'
  end
end
