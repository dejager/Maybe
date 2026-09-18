# Provenance

Maybe is an independent native Swift reimplementation of the small Probably 0.1
language described at https://probably-lang.southpolesteve.workers.dev/.
The original language design, syntax, and provider roles belong to that project.
This is not an official port or an endorsed release.

The downloadable reference interpreter was inspected outside this repository.
No upstream implementation files, website assets, or hosted recordings are
redistributed. Its download did not include an explicit license at inspection.
Maybe's Apache 2.0 license applies to the new implementation and original examples here;
it does not assign permissions to upstream material.

The JSON fixtures in Tests/MaybeTests/Fixtures are original synthetic programs and
model responses executed against the reference interpreter, with no live model
calls. The generation script is included to make their provenance reproducible.

Monogram (https://github.com/johnsoncodehk/monogram) was reviewed as related work
on grammar-derived tooling and conformance checking. No Monogram code is bundled
and it is not a dependency.
