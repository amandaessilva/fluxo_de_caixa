import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["menu"]
  toggle(event) {
    const expanded = event.currentTarget.getAttribute("aria-expanded") === "true"
    event.currentTarget.setAttribute("aria-expanded", String(!expanded))
    this.menuTarget.classList.toggle("is-open", !expanded)
  }
}
