import { Controller } from "@hotwired/stimulus"

// Toggles a roadmap phase's card list open/closed. The disclosure is a
// native <button>, so Enter/Space already dispatch click for free; we just
// keep aria-expanded and the body's `hidden` attribute in sync. There's no
// transition here for prefers-reduced-motion to override, and the global
// reset already strips any that get added later.
export default class extends Controller {
  static targets = [ "button", "body" ]

  toggle() {
    const expanded = this.buttonTarget.getAttribute("aria-expanded") === "true"

    this.buttonTarget.setAttribute("aria-expanded", !expanded)
    this.bodyTarget.toggleAttribute("hidden", expanded)
  }
}
