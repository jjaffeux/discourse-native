---
title: Scroll Area
description: Augments native scroll functionality for custom, cross-browser styling.
base: base
component: true
links:
  doc: https://base-ui.com/react/components/scroll-area
  api: https://base-ui.com/react/components/scroll-area#api-reference
---

```tsx
import * as React from "react"

import { ScrollArea } from "@/components/ui/scroll-area"
import { Separator } from "@/components/ui/separator"

const tags = Array.from({ length: 50 }).map(
  (_, i, a) => `v1.2.0-beta.${a.length - i}`
)

export function ScrollAreaDemo() {
  return (
    <ScrollArea className="h-72 w-48 rounded-md border">
      <div className="p-4">
        <h4 className="mb-4 text-sm leading-none font-medium">Tags</h4>
        {tags.map((tag) => (
          <React.Fragment key={tag}>
            <div className="text-sm">{tag}</div>
            <Separator className="my-2" />
          </React.Fragment>
        ))}
      </div>
    </ScrollArea>
  )
}

```

## Installation

<CodeTabs>

<TabsList>
  <TabsTrigger value="cli">Command</TabsTrigger>
  <TabsTrigger value="manual">Manual</TabsTrigger>
</TabsList>
<TabsContent value="cli">

```bash
npx shadcn@latest add scroll-area
```

</TabsContent>

<TabsContent value="manual">

<Steps className="mb-0 pt-2">

<Step>Install the following dependencies:</Step>

```bash
npm install @base-ui/react
```

<Step>Copy and paste the following code into your project.</Step>

<ComponentSource
  name="scroll-area"
  title="components/ui/scroll-area.tsx"
  styleName="base-nova"
/>

<Step>Update the import paths to match your project setup.</Step>

</Steps>

</TabsContent>

</CodeTabs>

## Usage

```tsx showLineNumbers
import { ScrollArea, ScrollBar } from "@/components/ui/scroll-area"
```

```tsx showLineNumbers
<ScrollArea className="h-[200px] w-[350px] rounded-md border p-4">
  Your scrollable content here.
</ScrollArea>
```

## Composition

Use the following composition to build a `ScrollArea`:

```text
ScrollArea
└── ScrollBar
```

## Horizontal

Use `ScrollBar` with `orientation="horizontal"` for horizontal scrolling.

```tsx
import * as React from "react"
import Image from "next/image"

import { ScrollArea, ScrollBar } from "@/components/ui/scroll-area"

export interface Artwork {
  artist: string
  art: string
}

export const works: Artwork[] = [
  {
    artist: "Ornella Binni",
    art: "https://images.unsplash.com/photo-1465869185982-5a1a7522cbcb?auto=format&fit=crop&w=300&q=80",
  },
  {
    artist: "Tom Byrom",
    art: "https://images.unsplash.com/photo-1548516173-3cabfa4607e9?auto=format&fit=crop&w=300&q=80",
  },
  {
    artist: "Vladimir Malyavko",
    art: "https://images.unsplash.com/photo-1494337480532-3725c85fd2ab?auto=format&fit=crop&w=300&q=80",
  },
]

export function ScrollAreaHorizontalDemo() {
  return (
    <ScrollArea className="w-96 rounded-md border whitespace-nowrap">
      <div className="flex w-max space-x-4 p-4">
        {works.map((artwork) => (
          <figure key={artwork.artist} className="shrink-0">
            <div className="overflow-hidden rounded-md">
              <Image
                src={artwork.art}
                alt={`Photo by ${artwork.artist}`}
                className="aspect-[3/4] h-fit w-fit object-cover"
                width={300}
                height={400}
              />
            </div>
            <figcaption className="pt-2 text-xs text-muted-foreground">
              Photo by{" "}
              <span className="font-semibold text-foreground">
                {artwork.artist}
              </span>
            </figcaption>
          </figure>
        ))}
      </div>
      <ScrollBar orientation="horizontal" />
    </ScrollArea>
  )
}

```

## RTL

To enable RTL support in shadcn/ui, see the [RTL configuration guide](/docs/rtl).

```tsx
"use client"

import * as React from "react"

import {
  useTranslation,
  type Translations,
} from "@/components/language-selector"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Separator } from "@/components/ui/separator"

const tags = Array.from({ length: 50 }).map(
  (_, i, a) => `v1.2.0-beta.${a.length - i}`
)

const translations: Translations = {
  en: {
    dir: "ltr",
    values: {
      tags: "Tags",
    },
  },
  ar: {
    dir: "rtl",
    values: {
      tags: "العلامات",
    },
  },
  he: {
    dir: "rtl",
    values: {
      tags: "תגיות",
    },
  },
}

export function ScrollAreaRtl() {
  const { dir, t } = useTranslation(translations, "ar")

  return (
    <ScrollArea className="h-72 w-48 rounded-md border" dir={dir}>
      <div className="p-4">
        <h4 className="mb-4 text-sm leading-none font-medium">{t.tags}</h4>
        {tags.map((tag) => (
          <React.Fragment key={tag}>
            <div className="text-sm">{tag}</div>
            <Separator className="my-2" />
          </React.Fragment>
        ))}
      </div>
    </ScrollArea>
  )
}

```

## API Reference

See the [Base UI Scroll Area](https://base-ui.com/react/components/scroll-area#api-reference) documentation.
