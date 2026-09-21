import { site } from "../data/site";
import { Button } from "./ui/button";
import { GitHubLogo, Logo } from "./ui/icon";

// The mark alone on a violet glow, so the page ends on the brand.
function GlowingMark() {
  return (
    <span className="relative mx-auto flex size-28 items-center justify-center sm:size-32">
      <span
        aria-hidden="true"
        className="mark-bloom pointer-events-none absolute -inset-32"
      />
      <Logo size={72} className="relative" />
    </span>
  );
}

export function Support() {
  return (
    <section id="support" className="px-4 pb-24 pt-24 text-center sm:px-10 ">
      <div aria-hidden="true">
        <GlowingMark />
      </div>
      <h2 className="mx-auto mt-14 max-w-2xl text-closing">
        Keep Delores free.
      </h2>
      <p className="mx-auto mt-4 max-w-lg text-pretty text-body-lg text-fg-muted">
        Delores has no account, no telemetry and nothing that phones home. If it
        has earned a place on your Mac, the repository is where it keeps moving.
      </p>
      {/* There was a "Support development" button here. Its URL was upstream's Polar page, so a
          click paid a different project's author. Delores has no funding link of its own yet —
          add one here (and to site.support) when it does, rather than restoring that one. */}
      <div className="mt-8 flex flex-wrap justify-center gap-3">
        <Button href={site.repo} size="lg">
          <GitHubLogo size={16} />
          Star on GitHub
        </Button>
      </div>
    </section>
  );
}
