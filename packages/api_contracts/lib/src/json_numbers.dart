/// JSON integer bounds shared by the API contracts.
///
/// JSON numbers are consumed by Flutter Web, where integers are represented as
/// IEEE-754 doubles. Only integers up to `2^53 - 1` are exactly representable
/// there, and `dart2js` rejects larger integer literals at compile time even
/// though VM tests accept them.
library;

/// Largest integer exactly representable in JavaScript (`2^53 - 1`).
const int maxJsonSafeInteger = 9007199254740991;

/// Largest integer that can be incremented by one and still be exactly
/// representable by every supported client.
const int maxIncrementableJsonSafeInteger = maxJsonSafeInteger - 1;
