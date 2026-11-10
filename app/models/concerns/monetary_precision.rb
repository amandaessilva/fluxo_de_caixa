# Rejeita frações de centavo antes de o tipo DECIMAL arredondar o valor.
module MonetaryPrecision
  extend ActiveSupport::Concern
  included do
    validate :money_has_two_decimal_places
  end
  private
  def money_has_two_decimal_places
    field = has_attribute?(:amount) ? :amount : :opening_balance
    raw = public_send("#{field}_before_type_cast")
    return if raw.nil?
    value = BigDecimal(raw.to_s)
    errors.add(field, 'deve ter no máximo duas casas decimais') unless value.finite? && (value * 100).frac.zero?
  rescue ArgumentError
    errors.add(field, 'não é um valor monetário válido')
  end
end
