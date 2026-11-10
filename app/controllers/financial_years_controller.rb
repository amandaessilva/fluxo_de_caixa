class FinancialYearsController < ApplicationController
  def create
    balance = params[:opening_balance].present? ? money_param(params[:opening_balance]) : nil
    year = GoogleCalendarEntrySync.suppress_callbacks do
      YearBuilder.call(params[:year], opening_balance: balance)
    end
    sync_google_calendar_if_connected
    session[:year] = year.year
    redirect_to root_path(year: year.year), notice: 'Ano disponível, com limites e contas fixas previstos.'
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    redirect_to settings_path, alert: e.message
  end
end
