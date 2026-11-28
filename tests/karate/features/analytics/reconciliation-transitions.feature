Feature: Polling reconciliation events feed escrow analytics

  Background:
    * url baseUrl
    * header x-hasura-role = 'host'
    * configure afterScenario = function(){ db.execute("DELETE FROM safetrust.trustless_work_webhook_events WHERE contract_id LIKE 'test-ana-reconcile-%'"); }
    * db.execute(karate.read('file:tests/fixtures/analytics/seed-reconciliation-transitions.sql'))

  Scenario: funding, release, and dispute are counted once after a replay
    Given request
      """
      {
        "query": "query { getEscrowAnalyticsByDay(args: {p_start_date: \"2026-10-15\", p_end_date: \"2026-10-15\", p_tenant_id: \"safetrust\"}) { day webhook_records lifecycle_events processed_events } }"
      }
      """
    When method POST
    Then status 200
    And match response.errors == '#notpresent'
    And match response.data.getEscrowAnalyticsByDay[0] ==
      { day: '2026-10-15', webhook_records: 3, lifecycle_events: 3, processed_events: 3 }
