module ApplicationHelper
  def brl(value) = number_to_currency(value || 0, unit: 'R$', separator: ',', delimiter: '.', format: '%u %n')
  def month_name(month) = I18n.t('date.month_names')[month]
  def month_options = (1..12).map { |m| [month_name(m).capitalize, m] }
  def kind_options = Entry::KINDS.map { |key, label| [label, key] }
  def status_options = Entry::STATUSES.map { |key, label| [label, key] }
  def category_options = Category.order(:name).pluck(:name, :id)
  def percent(spent, limit)
    limit.to_d.positive? ? [(spent.to_d / limit.to_d * 100).round, 100].min : (spent.to_d.positive? ? 100 : 0)
  end
end
