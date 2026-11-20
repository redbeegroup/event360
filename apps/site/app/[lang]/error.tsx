'use client';

/** Shown when the event data can't be loaded (API down or slow). */
export default function ErrorPage({ reset }: { reset: () => void }) {
  return (
    <div className="wrap" style={{ padding: '80px 0' }}>
      <h1 style={{ fontSize: 'clamp(1.8rem, 4vw, 2.6rem)' }}>Events couldn’t be loaded</h1>
      <p className="muted" style={{ marginTop: 12, maxWidth: '50ch' }}>
        Please try again in a moment.
        <br />
        <span lang="my">ပွဲများကို ဖွင့်၍ မရပါ။ ခဏနေ ထပ်ကြိုးစားပါ။</span>
      </p>
      <button className="btn btn-night" style={{ marginTop: 24 }} onClick={() => reset()}>
        Try again · ထပ်ကြိုးစားမည်
      </button>
    </div>
  );
}
