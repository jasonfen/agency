# `agency-count`: sends one anonymous event to PostHog (installer/count.sh).
# The installer uses it, and the installed machine once, on its first start.
{
  writeShellApplication,
  coreutils,
  curl,
  gnused,
  jq,
  rev ? "",
}:
writeShellApplication {
  name = "agency-count";
  runtimeInputs = [
    coreutils
    curl
    gnused
    jq
  ];
  text = ''
    AGENCY_COUNT_REV=${builtins.substring 0 12 rev}
    ${builtins.readFile ../installer/count.sh}
  '';
}
