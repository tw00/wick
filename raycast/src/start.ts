import { LaunchProps } from "@raycast/api";
import { send } from "./wick";

export default async function main(props: LaunchProps<{ arguments: { duration?: string } }>) {
  const d = props.arguments.duration?.trim();
  await send("start", d, d ? `Wick: ${d}` : "Wick started");
}
