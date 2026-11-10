import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["count", "hint"]
  update() {
    const count = Number(this.countTarget.value)
    this.hintTarget.textContent = count > 1
      ? `Serão criadas ${count} parcelas planejadas. O valor total será dividido com ajuste exato de centavos; anos futuros serão criados quando necessário.`
      : "Um lançamento será criado na situação selecionada."
  }
}
