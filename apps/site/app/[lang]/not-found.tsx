import Link from 'next/link';

export default function NotFound() {
  return (
    <div className="wrap status-page">
      <h1 className="page-title">Not found</h1>
      <p className="muted" style={{ marginTop: 12, maxWidth: '50ch' }}>
        This page doesn’t exist, or the event is no longer listed.
        <br />
        <span lang="my">ဤစာမျက်နှာ မရှိပါ သို့မဟုတ် ပွဲကို ဖော်ပြခြင်း မရှိတော့ပါ။</span>
      </p>
      <Link className="btn btn-night" style={{ marginTop: 24 }} href="/events">Events · ပွဲများ</Link>
    </div>
  );
}
