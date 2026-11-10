class SettingsController < ApplicationController
  def show
    @years = FinancialYear.order(:year)
    @rules = RecurringRule.includes(:category).order(:description)
    @google_calendar_configured = GoogleCalendarApi.configured?
    @google_calendar_connected = current_user.google_calendar_connected?
  end
  def update
    year = FinancialYear.find(params[:financial_year_id])
    attrs = { opening_balance: money_param(params[:opening_balance]) }
    attrs[:previous_year] = nil if params[:independent] == '1'
    year.update!(attrs)
    redirect_to settings_path(year: year.year), notice: 'Saldo inicial atualizado.'
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    redirect_to settings_path, alert: e.message
  end
end
