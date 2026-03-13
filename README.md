## What is this?

This repository has a terrible script (which you can ignore) and some illustrations of glams in the `examples` directory.

## Are these glams or not?

They're illustrations.

Per our discussions

> ...the contents of a glam start at the end of its resolved path.

Once ingested, `xyzzy.0001` would resolve to an OCFL object, and the glam starts at the `content` directory:

```
1e8/
└── ec2/
    └── b1d/
        └── 1e8ec2b1d14b8c7a0b76f5300dccf85472bd63ab09d1524f2d6d360a1736efe3/
            ├── 0=ocfl_object_1.1
            ├── inventory.json
            ├── inventory.json.sha512
            └── v1/
                └── content
```

In a submission package --- you'll recall this is a BagIt container --- the glam would start under `data`:

```
[xyzzy.0001.20260309095100]/
└── data/
    └── xyzzy.0001
```

...but these illustrations are modeling **complete header data**, while the submission package would have a subset of these properties.

Sorry about that.

## How to validate with the schemas?

One option, after installing `ajv` (this is global, you do you):

```
npm install -g ajv-cli ajv-formats
```

Then:

```
ajv validate --spec=draft2020 -c ajv-formats --validate-formats=true -s ./schemas/submission_header.json -d examples/nested/tinder.3/.dor/core.dor.json.json

# to validate against the preservation header schema
ajv validate --spec=draft2020 -c ajv-formats --validate-formats=true -s ./schemas/preservation_header.json -r ./schemas/submission_header.json -d examples/nested/tinder.3/.dor/core.dor.json.json
```

