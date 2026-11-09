/** Splits a config text on blank lines into paragraphs (ADD-02 §7). */
export default function Paragraphs({ text }: { text: string }) {
  return <>{text.split(/\n\s*\n/).map((p, i) => <p key={i}>{p}</p>)}</>
}
