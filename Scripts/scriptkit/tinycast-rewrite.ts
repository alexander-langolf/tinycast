// Name: Tinycast Rewrite
import "@johnlindquist/kit";

// Script Kit's PATH rarely includes the bundled CLI, so the Dev build's copy is the fallback.
const cli =
  process.env.TINYCAST_CLI ??
  home("Library/Developer/Xcode/DerivedData/Tinycast-bhizcfwkzzcrgjgutaacdzryskwx/Build/Products/Debug/Tinycast Dev.app/Contents/Helpers/tinycast");

const args = JSON.stringify({ action: "rewrite", apply: true });
const { stdout } = await $`${cli} call quick_action_run --args ${args} --channel dev`;
const result = JSON.parse(stdout);
await notify({
  title: "Tinycast Rewrite",
  message: result.applied ? "Selection rewritten." : "The selection could not be replaced.",
});
