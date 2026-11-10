class RecurringRulesController < ApplicationController
  def create
    attrs = params.require(:recurring_rule).permit(:description, :category_id, :kind, :amount, :day, :starts_on, :ends_on, :payment_method).to_h
    attrs['amount'] = money_param(attrs['amount'])
    GoogleCalendarEntrySync.suppress_callbacks do
      RecurringRule.transaction do
        rule = RecurringRule.create!(attrs)
        FinancialYear.find_each { |year| rule.materialize!(year) }
      end
    end
    sync_google_calendar_if_connected
    redirect_to settings_path, notice: 'Conta fixa cadastrada e previsões geradas nos anos existentes.'
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    redirect_to settings_path, alert: e.message
  end
  def destroy
    rule = RecurringRule.find(params[:id])
    rule.destroy!
    redirect_to settings_path, notice: 'Regra removida. Lançamentos já gerados foram preservados e podem ser editados individualmente.', status: :see_other
  end
end
