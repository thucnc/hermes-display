/// Which brain answers turns. Speech-to-text always runs on the hub.
enum BrainMode {
  hub,
  gemini;

  static BrainMode? fromName(String? raw) => values.asNameMap()[raw];
}
