<script>
  import MarketingShell from '$lib/components/MarketingShell.svelte';
  import SocialMeta from '$lib/components/SocialMeta.svelte';

  const description =
    "What Vibes collects, shares with friends, sends to service providers, and keeps on the relay.";
</script>

<svelte:head>
  <title>Privacy — Vibes</title>
  <meta name="description" content={description} />
</svelte:head>

<SocialMeta title="Privacy — Vibes" {description} path="/privacy" />

<MarketingShell>
  {#snippet children()}
    <article class="privacy-page shell">
      <div class="eyebrow"><span class="lockpip"></span> Privacy notice</div>
      <h1>Sharing, without sharing <span class="spectrum-text">your code.</span></h1>
      <p class="lede">
        Vibes is an ambient presence app for coding friends. Sharing activity is the point of
        the app, so this notice describes exactly what leaves your Mac and what does not.
      </p>
      <p class="effective">Effective August 8, 2026</p>

      <section>
        <h2>At a glance</h2>
        <p>
          This table is the practical version of the policy. The sections below explain retention,
          defaults, and the less obvious edge cases.
        </p>
        <div class="table-wrap">
          <table>
            <caption>Vibes data sharing at a glance</caption>
            <thead>
              <tr>
                <th scope="col">What leaves your machine</th>
                <th scope="col">Who can see it</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td data-label="What leaves your machine">
                  <strong>Identity and account</strong>
                  Display name, timezone, and device label. The relay assigns your user ID and
                  handle.
                </td>
                <td data-label="Who can see it">
                  Accepted friends see your ID, handle, and display name. The relay operator sees
                  the account and device records. Anyone with an open invite link can see the
                  inviter's display name.
                </td>
              </tr>
              <tr>
                <td data-label="What leaves your machine">
                  <strong>Presence and status</strong>
                  Online or Offline mode, update time, local-day metadata, and your optional
                  manual status.
                </td>
                <td data-label="Who can see it">
                  Accepted friends and the relay operator. Offline hides the online indicator but
                  does not stop periodic sharing while Vibes is running.
                </td>
              </tr>
              <tr>
                <td data-label="What leaves your machine">
                  <strong>Git activity</strong>
                  Commits, files changed, insertions, deletions, repositories touched, shared repo
                  names or aliases. The relay uses those aggregates to derive your streak and
                  baseline. On days with up to 150 commits, pseudonymous commit fingerprints,
                  times, and counts are also sent. Commit subjects, descriptions, and messages are
                  never sent.
                </td>
                <td data-label="Who can see it">
                  Accepted friends see the activity summary, repo names or aliases, streak, and
                  baseline. The relay operator can also access the per-commit details used for
                  cross-device deduplication.
                </td>
              </tr>
              <tr>
                <td data-label="What leaves your machine">
                  <strong>Optional music</strong>
                  Player, track, artist, playback state, and capture time when enabled.
                </td>
                <td data-label="Who can see it">Accepted friends and the relay operator.</td>
              </tr>
              <tr>
                <td data-label="What leaves your machine">
                  <strong>Optional weather</strong>
                  Your city or coordinates go to Open-Meteo. Conditions and temperature go to the
                  relay; the city is included only when Share City is enabled.
                </td>
                <td data-label="Who can see it">
                  Open-Meteo receives the lookup and ordinary network data such as your IP address.
                  Accepted friends and the relay operator see the resulting weather card.
                </td>
              </tr>
              <tr>
                <td data-label="What leaves your machine">
                  <strong>Profile icon</strong>
                  The generated PNG, your avatar prompt, and its style when you save it.
                </td>
                <td data-label="Who can see it">
                  Accepted friends and the relay operator. Anyone who obtains the public,
                  hard-to-guess image URL can view the PNG.
                </td>
              </tr>
              <tr>
                <td data-label="What leaves your machine">
                  <strong>Network Pulse contribution</strong>
                  Your aggregate daily Git totals contribute to a 14-day service-wide summary.
                </td>
                <td data-label="Who can see it">
                  Every signed-in relay user sees the same aggregate without names or handles. The
                  relay operator can access the underlying account-level activity records.
                </td>
              </tr>
              <tr>
                <td data-label="What leaves your machine">
                  <strong>Account sync credential</strong>
                  Relay address, handle, display name, and a bearer credential are placed in iCloud
                  Keychain.
                </td>
                <td data-label="Who can see it">
                  Your other Macs connected to the same iCloud Keychain account can use the
                  credential to authenticate the Vibes account and mint a device token.
                </td>
              </tr>
              <tr>
                <td data-label="What leaves your machine">
                  <strong>Website and relay requests</strong>
                  IP address, timestamp, requested path, response status, referrer, and user agent.
                </td>
                <td data-label="Who can see it">The relay operator through server access logs.</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section class="local-only">
        <h2>What stays on your Mac</h2>
        <p>
          Vibes does not intentionally upload source code, file contents, raw repository paths,
          branch names, commit messages, filenames, your local Git name or email, editor or
          process history, coding-tool attribution, AI-assistant prompts, or agent transcripts.
          The profile-icon prompt and other text you enter yourself — such as a status or
          repository alias — are sent as entered, so do not put secrets in those fields.
        </p>
      </section>

      <section>
        <h2>Account and device data</h2>
        <p>
          Signing up creates a Vibes account and a bearer token. No email address or password is
          required. The relay stores your handle, display name, timezone, account timestamps,
          device identifiers and labels, hashed token records and last-used times, invitations,
          friend relationships, and administrative audit records. Invite and device-link codes
          are stored as hashes.
        </p>
        <p>
          Release builds store the working token in macOS Keychain. Vibes also places the relay
          address, handle, display name, and a bearer credential in iCloud Keychain so your other
          Macs can offer to join the same account. That credential can authenticate the account
          and mint a new device token. Apple handles the synchronization; it may not occur when
          iCloud Keychain is disabled.
        </p>
      </section>

      <section>
        <h2>Presence and activity</h2>
        <p>
          While Vibes is running, it scans configured Git repositories and normally publishes
          your selected presence mode and enabled activity cards about every three minutes. The
          relay considers the newest Online publication online for ten minutes. This indicates
          that Vibes is online on your Mac; it does not prove that you were actively typing
          throughout that period.
        </p>
        <p>
          Selecting Offline hides your online indicator, but it is not a pause-sharing control.
          The running app continues its periodic scans and can publish updated Git, music, and
          weather cards with an offline presence. To stop those publications, quit Vibes or
          disable the relevant cards or repositories.
        </p>
        <p>
          A status includes your local day and timezone boundaries, update time, manual status,
          and enabled cards. Git cards can include commit counts, files changed, insertions,
          deletions, repositories touched, and shared repository names or aliases. Repository
          name sharing and aggregate Git cards are enabled by default; individual repositories
          can be hidden or have alias sharing disabled.
        </p>
        <p>
          For cross-device counting on days with up to 150 commits, the app sends a deterministic
          SHA-256 fingerprint derived from each commit hash, plus its time and aggregate change
          counts. On a day with more than 150 commits, it sends no per-commit details. The raw
          commit hash is not sent and these details are not returned in friend feeds. The
          fingerprint is pseudonymous, not anonymous: someone who already knows a commit hash can
          calculate its fingerprint and compare it with relay data they can access.
        </p>
      </section>

      <section>
        <h2>Optional features and other services</h2>
        <p>
          Music and weather sharing are off by default. When music sharing is enabled, Vibes reads
          the current Spotify or Apple Music track locally and sends the player, track, artist,
          playback state, and capture time to the relay for your friends. Vibes does not send
          listening credentials to the relay.
        </p>
        <p>
          Weather uses Open-Meteo. If you enter a city, that city is sent to Open-Meteo's geocoding
          service. If you use Location Services, coordinates are sent to Open-Meteo's forecast
          service. The relay receives the resulting conditions and temperature; it receives the
          city only when you enable Share City. Open-Meteo receives ordinary network information,
          including your IP address, under its own privacy terms.
        </p>
        <p>
          Profile icons are generated on your Mac. When you save one, Vibes uploads the PNG, your
          profile-icon prompt, and the selected style to the relay. Friends receive the current
          image URL. Avatar files use public, hard-to-guess URLs rather than authenticated image
          requests, so anyone who obtains a URL can view that image.
        </p>
      </section>

      <section>
        <h2>Network Pulse</h2>
        <p>
          Every signed-in user receives the same Network Pulse: totals and trends computed from
          aggregate Git activity across all users of that relay, not just their friends. It covers
          a trailing 14-day window. Names, handles, devices, avatars, and repository names are not
          included. Numeric activity and contributor counts are suppressed on days with fewer
          than three contributors, although the app may still say that people are active. Like
          any small-group aggregate, the Pulse may still support inferences when someone already
          knows other contributors' activity.
        </p>
      </section>

      <section>
        <h2>Relay access, security, and logs</h2>
        <p>
          Friend-feed data is visible to accepted friends. Anyone holding a still-open invite link
          can retrieve the inviter's display name without signing in. Network Pulse aggregates are
          visible to signed-in users. The relay operator can access stored account, relationship,
          status, activity, avatar, prompt, and operational data to run and support the service.
          Vibes uses HTTPS in transit and stores bearer tokens as hashes on the relay, but friend
          data is not end-to-end encrypted and the relay can read it.
        </p>
        <p>
          The web server records ordinary access logs, including IP address, timestamp, requested
          path, response status, referrer, and user agent. Those logs are currently retained in up
          to 14 daily rotations. Requested paths can contain invite codes, so treat an invite link
          as a secret until it is accepted, revoked, or expires. Vibes does not run an advertising
          or product-analytics SDK on the website or in the app.
        </p>
      </section>

      <section>
        <h2>Retention and deletion</h2>
        <p>
          The relay keeps the latest status for each device and retains daily activity and commit
          fingerprints for streaks, baselines, and cross-device deduplication. Account, device,
          friendship, invitation, and administrative records remain until they are deleted by the
          operator. Vibes does not currently apply an automatic expiry period to those records.
        </p>
        <p>
          Saving a new profile icon or clearing the current one does not delete older avatar rows
          or image files. Their immutable URLs may continue to work if someone retained a link.
          There is not yet a self-service account export or deletion control. An operator can
          delete the account-linked database records, but a deletion audit entry containing the
          handle remains and the current deletion path does not remove historical avatar files.
        </p>
      </section>

      <section>
        <h2>Questions and requests</h2>
        <p>
          For a privacy question, correction, or account deletion request, email
          <a href="mailto:marcus@vorwaller.net">marcus@vorwaller.net</a>. You can also inspect the
          <a href="https://github.com/marcus/vibes">source code</a>. Do not send bearer tokens,
          invite codes, or other secrets by email or in a public issue.
        </p>
      </section>

      <div class="foot-cta">
        <a class="btn btn-primary" href="/download">
          <svg class="apple" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M5 21h14"/></svg>
          Download for Mac
        </a>
      </div>
    </article>
  {/snippet}
</MarketingShell>

<style>
  .privacy-page {
    max-width: 820px;
    margin: 0 auto;
    padding: var(--s-12) var(--s-6) var(--s-12);
  }

  .eyebrow {
    display: inline-flex; align-items: center; gap: var(--s-2);
    font-size: var(--t-xs); font-weight: 600;
    letter-spacing: 0.14em; text-transform: uppercase;
    color: var(--text-tertiary); margin-bottom: var(--s-5);
  }
  .eyebrow .lockpip { width: 7px; height: 7px; border-radius: 50%; background: var(--v-cyan); box-shadow: 0 0 10px var(--v-cyan); }

  .privacy-page h1 {
    font-size: clamp(36px, 5.5vw, var(--t-5xl));
    font-weight: 800; letter-spacing: -0.04em; line-height: 1.0;
  }
  .lede {
    max-width: 660px; margin: var(--s-5) 0 0;
    font-size: clamp(16px, 2vw, var(--t-lg));
    color: var(--text-secondary); line-height: 1.5;
  }
  .effective {
    margin-top: var(--s-3);
    color: var(--text-tertiary);
    font-size: var(--t-sm);
  }

  section {
    margin-top: var(--s-9);
  }
  section h2 {
    margin-bottom: var(--s-3);
    color: var(--text-primary);
    font-size: var(--t-lg);
    font-weight: 700;
    letter-spacing: -0.01em;
  }
  section p {
    color: var(--text-secondary);
    font-size: var(--t-base);
    line-height: 1.6;
  }
  section p + p { margin-top: var(--s-4); }
  section a { color: var(--accent-default); }

  .table-wrap {
    margin-top: var(--s-5);
    overflow: hidden;
    background: var(--bg-secondary);
    border: 1px solid var(--border-subtle);
    border-radius: var(--r-lg);
  }
  table {
    width: 100%;
    border-collapse: collapse;
    table-layout: fixed;
  }
  caption {
    position: absolute;
    width: 1px;
    height: 1px;
    padding: 0;
    margin: -1px;
    overflow: hidden;
    clip: rect(0, 0, 0, 0);
    white-space: nowrap;
    border: 0;
  }
  th, td {
    width: 50%;
    padding: var(--s-5);
    text-align: left;
    vertical-align: top;
  }
  th {
    color: var(--text-primary);
    background: var(--bg-tertiary);
    font-size: var(--t-sm);
    font-weight: 700;
    letter-spacing: 0.01em;
  }
  th + th, td + td { border-left: 1px solid var(--border-subtle); }
  tbody tr { border-top: 1px solid var(--border-subtle); }
  td {
    color: var(--text-secondary);
    font-size: var(--t-sm);
    line-height: 1.55;
  }
  td strong {
    display: block;
    margin-bottom: var(--s-1);
    color: var(--text-primary);
    font-size: var(--t-base);
    font-weight: 650;
  }
  .local-only {
    padding: var(--s-6);
    background: var(--bg-secondary);
    border-radius: var(--r-lg);
  }

  .foot-cta { margin-top: var(--s-10); }

  @media (max-width: 640px) {
    .table-wrap { background: transparent; border: 0; border-radius: 0; }
    table, thead, tbody, tr, th, td { display: block; width: 100%; }
    thead {
      position: absolute;
      width: 1px;
      height: 1px;
      overflow: hidden;
      clip: rect(0, 0, 0, 0);
    }
    tbody { display: grid; gap: var(--s-4); }
    tbody tr {
      overflow: hidden;
      background: var(--bg-secondary);
      border: 1px solid var(--border-subtle);
      border-radius: var(--r-lg);
    }
    td { padding: var(--s-5); }
    td + td { border-top: 1px solid var(--border-subtle); border-left: 0; }
    td::before {
      display: block;
      margin-bottom: var(--s-2);
      color: var(--text-tertiary);
      content: attr(data-label);
      font-size: var(--t-xs);
      font-weight: 700;
      letter-spacing: 0.08em;
      text-transform: uppercase;
    }
  }
</style>
