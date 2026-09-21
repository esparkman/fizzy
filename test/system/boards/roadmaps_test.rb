require "application_system_test_case"

class Boards::RoadmapsTest < ApplicationSystemTestCase
  include ActionView::RecordIdentifier

  test "a board member visits the roadmap and sees phases, statuses, and step progress" do
    board = boards(:writebook)

    Current.set(session: sessions(:david)) do
      epic = board.cards.create!(title: "Ship the new nav", creator: users(:david), status: "published")
      epic.toggle_tag_with "phase:p1"
      epic.toggle_tag_with "type:epic"
      epic.toggle_tag_with "domain:design"
      epic.steps.create!(content: "Design", completed: true)
      epic.steps.create!(content: "Build", completed: true)
      epic.steps.create!(content: "Launch", completed: false)
      epic.close

      later_story = board.cards.create!(title: "Polish the empty states", creator: users(:david), status: "published")
      later_story.toggle_tag_with "phase:p2"

      board.cards.create!(title: "Investigate flaky test", creator: users(:david), status: "published")
    end

    sign_in_as(users(:david))
    visit board_roadmap_url(board)

    assert_equal [ "P1", "P2", "Unphased" ], all("section.roadmap__phase h2").map(&:text)

    within "#roadmap_phase_p1" do
      assert_selector ".roadmap__meter .roadmap__meter-segment--shipped"
      assert_text "1/1 shipped"

      assert_text "Ship the new nav"
      assert_selector ".roadmap__card .btn", text: /design/i
      assert_selector ".roadmap__card", text: /shipped/i
      assert_selector ".roadmap__card .roadmap__epic-badge", text: /\bepic\b/i
      assert_text "2/3"
    end

    within "#roadmap_phase_p2" do
      assert_text "Polish the empty states"
      assert_no_selector ".roadmap__card .roadmap__epic-badge"
    end

    within "#roadmap_phase_unphased" do
      assert_text "Investigate flaky test"
    end

    within ".roadmap__tiles" do
      assert_text "1/1"
      assert_text "Epics shipped"
    end
  end

  test "a board member collapses and expands a phase via its disclosure control" do
    board = boards(:writebook)

    Current.set(session: sessions(:david)) do
      board.cards.create!(title: "Ship the thing", creator: users(:david), status: "published").tap do |card|
        card.toggle_tag_with "phase:p1"
      end
    end

    sign_in_as(users(:david))
    visit board_roadmap_url(board)

    within "#roadmap_phase_p1" do
      disclosure = find(".roadmap__disclosure")
      body_selector = "##{disclosure['aria-controls']}"

      assert_equal "true", disclosure["aria-expanded"]
      assert_selector body_selector, visible: :visible
      assert_selector ".roadmap__card", text: "Ship the thing"

      disclosure.click

      assert_equal "false", find(".roadmap__disclosure")["aria-expanded"]
      assert_selector body_selector, visible: :hidden
      assert_no_selector ".roadmap__card", text: "Ship the thing"

      find(".roadmap__disclosure").click

      assert_equal "true", find(".roadmap__disclosure")["aria-expanded"]
      assert_selector body_selector, visible: :visible
      assert_selector ".roadmap__card", text: "Ship the thing"
    end
  end

  test "a board member visits the lanes view and sees cards grouped into status columns" do
    board = boards(:writebook)

    Current.set(session: sessions(:david)) do
      shipped = board.cards.create!(title: "Ship the new nav", creator: users(:david), status: "published")
      shipped.toggle_tag_with "phase:p1"
      shipped.close

      in_flight = board.cards.create!(title: "Rework the sidebar", creator: users(:david), status: "published")
      in_flight.toggle_tag_with "phase:p1"
      in_flight.triage_into(board.columns.create!(name: "Doing"))

      deferred = board.cards.create!(title: "Investigate flaky test", creator: users(:david), status: "published")
      deferred.toggle_tag_with "phase:p1"
      deferred.postpone

      planned = board.cards.create!(title: "Draft the onboarding flow", creator: users(:david), status: "published")
      planned.toggle_tag_with "phase:p1"
    end

    sign_in_as(users(:david))
    visit board_roadmap_url(board, view: "lanes")

    assert_selector "section.roadmap__band", text: "P1"

    within "#roadmap_band_p1" do
      shipped_lane = find(".roadmap__lane", text: /shipped/i)
      assert_equal "group", shipped_lane["role"],
        "expected each status lane to be a labeled group so screen reader users hear which status a chip belongs to"
      assert_selector "##{shipped_lane['aria-labelledby']}", text: "Shipped", visible: :all

      within shipped_lane do
        assert_text "Ship the new nav"
      end

      within ".roadmap__lane", text: /in flight/i do
        assert_text "Rework the sidebar"
      end

      within ".roadmap__lane", text: /not now/i do
        assert_text "Investigate flaky test"
      end

      within ".roadmap__lane", text: /planned/i do
        assert_text "Draft the onboarding flow"
      end

      within ".roadmap__lane", text: /stalled/i do
        assert_selector ".roadmap__lane-empty", text: "—"
      end
    end

    assert_text "1/4 shipped"
  end

  test "a board member switches between the list and lanes views and the choice persists" do
    board = boards(:writebook)

    Current.set(session: sessions(:david)) do
      card = board.cards.create!(title: "Ship the new nav", creator: users(:david), status: "published")
      card.toggle_tag_with "phase:p1"
    end

    sign_in_as(users(:david))
    visit board_roadmap_url(board)

    within ".roadmap__view-switch" do
      assert_equal "true", find_button("List")["aria-pressed"]
      assert_equal "false", find_button("Lanes")["aria-pressed"]
    end
    assert_selector ".roadmap__phase"
    assert_no_selector ".roadmap__band"

    within ".roadmap__view-switch" do
      click_on "Lanes"
    end

    assert_selector ".roadmap__band"
    assert_no_selector ".roadmap__phase"
    within ".roadmap__view-switch" do
      assert_equal "true", find_button("Lanes")["aria-pressed"]
      assert_equal "false", find_button("List")["aria-pressed"]
    end

    visit board_roadmap_url(board)

    assert_selector ".roadmap__band"
    assert_no_selector ".roadmap__phase"

    within ".roadmap__view-switch" do
      click_on "List"
    end

    assert_selector ".roadmap__phase"
    assert_no_selector ".roadmap__band"
  end

  test "a board with no cards shows an empty roadmap" do
    board = Board.create!(name: "Freshly minted", creator: users(:david), account: accounts(:"37s"))

    sign_in_as(users(:david))
    visit board_roadmap_url(board)

    within ".blank-slate" do
      assert_text "No roadmap yet"
      assert_text "phase:"
    end
  end

  test "a board member on a phone-width viewport sees no horizontal overflow and still sees status" do
    board = boards(:writebook)

    Current.set(session: sessions(:david)) do
      card = board.cards.create!(
        title: "Rebuild the notification preferences and delivery pipeline end to end",
        creator: users(:david),
        status: "published"
      )
      card.toggle_tag_with "phase:p1"
      card.toggle_tag_with "domain:design"
      card.toggle_tag_with "domain:engineering"
      card.toggle_tag_with "domain:marketing"
      card.steps.create!(content: "Design", completed: true)
      card.steps.create!(content: "Build", completed: false)
    end

    with_window_size(375, 700) do
      sign_in_as(users(:david))
      visit board_roadmap_url(board)

      assert_selector ".roadmap__card", text: "Rebuild the notification preferences"

      assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"),
        "expected the roadmap to fit within the phone viewport without horizontal overflow"

      within ".roadmap__card", text: "Rebuild the notification preferences" do
        assert_selector ".roadmap__marker .for-screen-reader", text: "Planned", visible: :all
        assert_no_selector ".roadmap__status-badge", visible: :visible
        assert_no_selector ".btn", text: "design", visible: :visible
        assert_selector ".roadmap__domains-count", text: "+3", visible: :visible

        # The domains list is visually clipped to 1x1px at this width (not display:none),
        # so a sighted mobile user sees nothing here -- Capybara's `visible: :visible`
        # filter can't tell a clipped sr-only element apart from an on-screen one, so
        # assert the clip directly instead.
        domains_rect = page.evaluate_script("document.querySelector('.roadmap__domains').getBoundingClientRect()")
        assert_equal 1, domains_rect["width"].to_i
        assert_equal 1, domains_rect["height"].to_i

        # The "+3" pill is a sighted shorthand and is aria-hidden; the actual
        # domain names must stay reachable by screen readers even though
        # they're visually hidden at this width.
        assert_selector ".roadmap__domains .btn", text: "design", visible: :all
        assert_selector ".roadmap__domains .btn", text: "engineering", visible: :all
        assert_selector ".roadmap__domains .btn", text: "marketing", visible: :all
      end
    end
  end

  test "a broadcast refresh shows a card closed elsewhere as shipped" do
    board = boards(:writebook)

    card = Current.set(session: sessions(:david)) do
      board.cards.create!(title: "Ship the thing", creator: users(:david), status: "published").tap do |card|
        card.toggle_tag_with "phase:p1"
      end
    end

    sign_in_as(users(:david))
    visit board_roadmap_url(board)

    card_row = "##{dom_id(card, :roadmap)}"
    assert_selector card_row, text: "Ship the thing"
    assert_no_selector "#{card_row} .roadmap__marker--shipped"

    close_card_elsewhere(card)

    # A page-refresh broadcast morphs the whole roadmap in place, and a
    # closed card's shipped status sorts it earlier in the phase -- so the
    # row itself can move. Asserting the shipped marker inside the id-scoped
    # row (rather than a "shipped" text regex over the row broadly) confirms
    # the settled post-broadcast state without caring where the row landed.
    within card_row do
      assert_selector ".roadmap__marker--shipped", wait: 5
      assert_selector ".roadmap__marker .for-screen-reader", text: "Shipped", visible: :all
    end
  end

  private
    # The Capybara browser session is reused across tests, so a resize here
    # would otherwise leak into whichever test runs next.
    def with_window_size(width, height)
      window = page.driver.browser.manage.window
      original_size = window.size
      window.resize_to(width, height)
      yield
    ensure
      window.resize_to(original_size.width, original_size.height)
    end

    def close_card_elsewhere(card)
      wait_for_cable_subscriptions
      Current.set(session: sessions(:david)) { card.close }
      perform_enqueued_jobs only: Turbo::Streams::BroadcastStreamJob
    end

    # A broadcast sent before the page's subscriptions are confirmed is lost.
    def wait_for_cable_subscriptions
      assert_selector "turbo-cable-stream-source[connected]", visible: :all
      assert_no_selector "turbo-cable-stream-source:not([connected])", visible: :all
    end
end
