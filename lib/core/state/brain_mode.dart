/// Which brain answers typed turns. Voice turns always use the hub, which
/// owns speech-to-text.
enum BrainMode {
  hub,
  gemini;

  static BrainMode? fromName(String? raw) => values.asNameMap()[raw];
}
