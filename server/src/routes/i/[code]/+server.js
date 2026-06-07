import { redirect } from "@sveltejs/kit";

export function GET({ params }) {
  throw redirect(308, `/invite/${encodeURIComponent(params.code)}`);
}
