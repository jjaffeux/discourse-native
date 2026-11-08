abstract mixin class Storable<T extends Storable<T>> {
  Object get storeId;

  /// Whether a replacement preserves the fields used by a loaded window.
  bool hasSameStoreStructure(covariant T incoming) => identical(this, incoming);

  T merge(covariant T incoming) => incoming;
}
