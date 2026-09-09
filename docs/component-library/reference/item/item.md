---
title: Item
description: A versatile component for displaying content with media, title, description, and actions.
base: base
component: true
---

```tsx
import { BadgeCheckIcon, ChevronRightIcon } from "lucide-react"

import { Button } from "@/components/ui/button"
import {
  Item,
  ItemActions,
  ItemContent,
  ItemDescription,
  ItemMedia,
  ItemTitle,
} from "@/components/ui/item"

export function ItemDemo() {
  return (
    <div className="flex w-full max-w-md flex-col gap-6">
      <Item variant="outline">
        <ItemContent>
          <ItemTitle>Basic Item</ItemTitle>
          <ItemDescription>
            A simple item with title and description.
          </ItemDescription>
        </ItemContent>
        <ItemActions>
          <Button variant="outline" size="sm">
            Action
          </Button>
        </ItemActions>
      </Item>
      <Item variant="outline" size="sm" render={<a href="#" />}>
        <ItemMedia>
          <BadgeCheckIcon className="size-5" />
        </ItemMedia>
        <ItemContent>
          <ItemTitle>Your profile has been verified.</ItemTitle>
        </ItemContent>
        <ItemActions>
          <ChevronRightIcon className="size-4" />
        </ItemActions>
      </Item>
    </div>
  )
}

```

The `Item` component is a straightforward flex container that can house nearly any type of content. Use it to display a title, description, and actions. Group it with the `ItemGroup` component to create a list of items.

## Installation

<CodeTabs>

<TabsList>
  <TabsTrigger value="cli">Command</TabsTrigger>
  <TabsTrigger value="manual">Manual</TabsTrigger>
</TabsList>
<TabsContent value="cli">

```bash
npx shadcn@latest add item
```

</TabsContent>

<TabsContent value="manual">

<Steps className="mb-0 pt-2">

<Step>Copy and paste the following code into your project.</Step>

<ComponentSource
  name="item"
  title="components/ui/item.tsx"
  styleName="base-nova"
/>

<Step>Update the import paths to match your project setup.</Step>

</Steps>

</TabsContent>

</CodeTabs>

## Usage

```tsx showLineNumbers
import {
  Item,
  ItemActions,
  ItemContent,
  ItemDescription,
  ItemMedia,
  ItemTitle,
} from "@/components/ui/item"
```

```tsx showLineNumbers
<Item>
  <ItemMedia variant="icon">
    <Icon />
  </ItemMedia>
  <ItemContent>
    <ItemTitle>Title</ItemTitle>
    <ItemDescription>Description</ItemDescription>
  </ItemContent>
  <ItemActions>
    <Button>Action</Button>
  </ItemActions>
</Item>
```

## Composition

Use the following composition to build an `Item`:

```text
ItemGroup
└── Item
    ├── ItemHeader
    ├── ItemMedia
    ├── ItemContent
    │   ├── ItemTitle
    │   └── ItemDescription
    ├── ItemActions
    └── ItemFooter
```

## Item vs Field

Use `Field` if you need to display a form input such as a checkbox, input, radio, or select.

If you only need to display content such as a title, description, and actions, use `Item`.

## Variant

Use the `variant` prop to change the visual style of the item.

```tsx
import { InboxIcon } from "lucide-react"

import {
  Item,
  ItemContent,
  ItemDescription,
  ItemMedia,
  ItemTitle,
} from "@/components/ui/item"

export function ItemVariant() {
  return (
    <div className="flex w-full max-w-md flex-col gap-6">
      <Item>
        <ItemMedia variant="icon">
          <InboxIcon />
        </ItemMedia>
        <ItemContent>
          <ItemTitle>Default Variant</ItemTitle>
          <ItemDescription>
            Transparent background with no border.
          </ItemDescription>
        </ItemContent>
      </Item>
      <Item variant="outline">
        <ItemMedia variant="icon">
          <InboxIcon />
        </ItemMedia>
        <ItemContent>
          <ItemTitle>Outline Variant</ItemTitle>
          <ItemDescription>
            Outlined style with a visible border.
          </ItemDescription>
        </ItemContent>
      </Item>
      <Item variant="muted">
        <ItemMedia variant="icon">
          <InboxIcon />
        </ItemMedia>
        <ItemContent>
          <ItemTitle>Muted Variant</ItemTitle>
          <ItemDescription>
            Muted background for secondary content.
          </ItemDescription>
        </ItemContent>
      </Item>
    </div>
  )
}

```

## Size

Use the `size` prop to change the size of the item. Available sizes are `default`, `sm`, and `xs`.

```tsx
import { InboxIcon } from "lucide-react"

import {
  Item,
  ItemContent,
  ItemDescription,
  ItemMedia,
  ItemTitle,
} from "@/components/ui/item"

export function ItemSizeDemo() {
  return (
    <div className="flex w-full max-w-md flex-col gap-6">
      <Item variant="outline">
        <ItemMedia variant="icon">
          <InboxIcon />
        </ItemMedia>
        <ItemContent>
          <ItemTitle>Default Size</ItemTitle>
          <ItemDescription>
            The standard size for most use cases.
          </ItemDescription>
        </ItemContent>
      </Item>
      <Item variant="outline" size="sm">
        <ItemMedia variant="icon">
          <InboxIcon />
        </ItemMedia>
        <ItemContent>
          <ItemTitle>Small Size</ItemTitle>
          <ItemDescription>A compact size for dense layouts.</ItemDescription>
        </ItemContent>
      </Item>
      <Item variant="outline" size="xs">
        <ItemMedia variant="icon">
          <InboxIcon />
        </ItemMedia>
        <ItemContent>
          <ItemTitle>Extra Small Size</ItemTitle>
          <ItemDescription>The most compact size available.</ItemDescription>
        </ItemContent>
      </Item>
    </div>
  )
}

```

## Icon

Use `ItemMedia` with `variant="icon"` to display an icon.

```tsx
import { ShieldAlertIcon } from "lucide-react"

import { Button } from "@/components/ui/button"
import {
  Item,
  ItemActions,
  ItemContent,
  ItemDescription,
  ItemMedia,
  ItemTitle,
} from "@/components/ui/item"

export function ItemIcon() {
  return (
    <div className="flex w-full max-w-lg flex-col gap-6">
      <Item variant="outline">
        <ItemMedia variant="icon">
          <ShieldAlertIcon />
        </ItemMedia>
        <ItemContent>
          <ItemTitle>Security Alert</ItemTitle>
          <ItemDescription>
            New login detected from unknown device.
          </ItemDescription>
        </ItemContent>
        <ItemActions>
          <Button size="sm" variant="outline">
            Review
          </Button>
        </ItemActions>
      </Item>
    </div>
  )
}

```

## Avatar

You can use `ItemMedia` with `variant="avatar"` to display an avatar.

```tsx
import { Plus } from "lucide-react"

import {
  Avatar,
  AvatarFallback,
  AvatarImage,
} from "@/components/ui/avatar"
import { Button } from "@/components/ui/button"
import {
  Item,
  ItemActions,
  ItemContent,
  ItemDescription,
  ItemMedia,
  ItemTitle,
} from "@/components/ui/item"

export function ItemAvatar() {
  return (
    <div className="flex w-full max-w-lg flex-col gap-6">
      <Item variant="outline">
        <ItemMedia>
          <Avatar className="size-10">
            <AvatarImage src="https://github.com/evilrabbit.png" />
            <AvatarFallback>ER</AvatarFallback>
          </Avatar>
        </ItemMedia>
        <ItemContent>
          <ItemTitle>Evil Rabbit</ItemTitle>
          <ItemDescription>Last seen 5 months ago</ItemDescription>
        </ItemContent>
        <ItemActions>
          <Button
            size="icon-sm"
            variant="outline"
            className="rounded-full"
            aria-label="Invite"
          >
            <Plus />
          </Button>
        </ItemActions>
      </Item>
      <Item variant="outline">
        <ItemMedia>
          <div className="flex -space-x-2 *:data-[slot=avatar]:ring-2 *:data-[slot=avatar]:ring-background *:data-[slot=avatar]:grayscale">
            <Avatar className="hidden sm:flex">
              <AvatarImage src="https://github.com/shadcn.png" alt="@shadcn" />
              <AvatarFallback>CN</AvatarFallback>
            </Avatar>
            <Avatar className="hidden sm:flex">
              <AvatarImage
                src="https://github.com/maxleiter.png"
                alt="@maxleiter"
              />
              <AvatarFallback>LR</AvatarFallback>
            </Avatar>
            <Avatar>
              <AvatarImage
                src="https://github.com/evilrabbit.png"
                alt="@evilrabbit"
              />
              <AvatarFallback>ER</AvatarFallback>
            </Avatar>
          </div>
        </ItemMedia>
        <ItemContent>
          <ItemTitle>No Team Members</ItemTitle>
          <ItemDescription>
            Invite your team to collaborate on this project.
          </ItemDescription>
        </ItemContent>
        <ItemActions>
          <Button size="sm" variant="outline">
            Invite
          </Button>
        </ItemActions>
      </Item>
    </div>
  )
}

```

## Image

Use `ItemMedia` with `variant="image"` to display an image.

```tsx
import Image from "next/image"

import {
  Item,
  ItemContent,
  ItemDescription,
  ItemGroup,
  ItemMedia,
  ItemTitle,
} from "@/components/ui/item"

const music = [
  {
    title: "Midnight City Lights",
    artist: "Neon Dreams",
    album: "Electric Nights",
    duration: "3:45",
  },
  {
    title: "Coffee Shop Conversations",
    artist: "The Morning Brew",
    album: "Urban Stories",
    duration: "4:05",
  },
  {
    title: "Digital Rain",
    artist: "Cyber Symphony",
    album: "Binary Beats",
    duration: "3:30",
  },
]

export function ItemImage() {
  return (
    <div className="flex w-full max-w-md flex-col gap-6">
      <ItemGroup className="gap-4">
        {music.map((song) => (
          <Item
            key={song.title}
            variant="outline"
            render={<a href="#" />}
            role="listitem"
          >
            <ItemMedia variant="image">
              <Image
                src={`https://avatar.vercel.sh/${song.title}`}
                alt={song.title}
                width={32}
                height={32}
                className="object-cover grayscale"
              />
            </ItemMedia>
            <ItemContent>
              <ItemTitle className="line-clamp-1">
                {song.title} -{" "}
                <span className="text-muted-foreground">{song.album}</span>
              </ItemTitle>
              <ItemDescription>{song.artist}</ItemDescription>
            </ItemContent>
            <ItemContent className="flex-none text-center">
              <ItemDescription>{song.duration}</ItemDescription>
            </ItemContent>
          </Item>
        ))}
      </ItemGroup>
    </div>
  )
}

```

## Group

Use `ItemGroup` to group related items together.

```tsx
import * as React from "react"
import { PlusIcon } from "lucide-react"

import {
  Avatar,
  AvatarFallback,
  AvatarImage,
} from "@/components/ui/avatar"
import { Button } from "@/components/ui/button"
import {
  Item,
  ItemActions,
  ItemContent,
  ItemDescription,
  ItemGroup,
  ItemMedia,
  ItemSeparator,
  ItemTitle,
} from "@/components/ui/item"

const people = [
  {
    username: "shadcn",
    avatar: "https://github.com/shadcn.png",
    email: "shadcn@vercel.com",
  },
  {
    username: "maxleiter",
    avatar: "https://github.com/maxleiter.png",
    email: "maxleiter@vercel.com",
  },
  {
    username: "evilrabbit",
    avatar: "https://github.com/evilrabbit.png",
    email: "evilrabbit@vercel.com",
  },
]

export function ItemGroupExample() {
  return (
    <ItemGroup className="max-w-sm">
      {people.map((person, index) => (
        <Item key={person.username} variant="outline">
          <ItemMedia>
            <Avatar>
              <AvatarImage src={person.avatar} className="grayscale" />
              <AvatarFallback>{person.username.charAt(0)}</AvatarFallback>
            </Avatar>
          </ItemMedia>
          <ItemContent className="gap-1">
            <ItemTitle>{person.username}</ItemTitle>
            <ItemDescription>{person.email}</ItemDescription>
          </ItemContent>
          <ItemActions>
            <Button variant="ghost" size="icon" className="rounded-full">
              <PlusIcon />
            </Button>
          </ItemActions>
        </Item>
      ))}
    </ItemGroup>
  )
}

```

## Header

Use `ItemHeader` to add a header above the item content.

```tsx
import Image from "next/image"

import {
  Item,
  ItemContent,
  ItemDescription,
  ItemGroup,
  ItemHeader,
  ItemTitle,
} from "@/components/ui/item"

const models = [
  {
    name: "v0-1.5-sm",
    description: "Everyday tasks and UI generation.",
    image:
      "https://images.unsplash.com/photo-1650804068570-7fb2e3dbf888?q=80&w=640&auto=format&fit=crop",
    credit: "Valeria Reverdo on Unsplash",
  },
  {
    name: "v0-1.5-lg",
    description: "Advanced thinking or reasoning.",
    image:
      "https://images.unsplash.com/photo-1610280777472-54133d004c8c?q=80&w=640&auto=format&fit=crop",
    credit: "Michael Oeser on Unsplash",
  },
  {
    name: "v0-2.0-mini",
    description: "Open Source model for everyone.",
    image:
      "https://images.unsplash.com/photo-1602146057681-08560aee8cde?q=80&w=640&auto=format&fit=crop",
    credit: "Cherry Laithang on Unsplash",
  },
]

export function ItemHeaderDemo() {
  return (
    <div className="flex w-full max-w-xl flex-col gap-6">
      <ItemGroup className="grid grid-cols-3 gap-4">
        {models.map((model) => (
          <Item key={model.name} variant="outline">
            <ItemHeader>
              <Image
                src={model.image}
                alt={model.name}
                width={128}
                height={128}
                className="aspect-square w-full rounded-sm object-cover"
              />
            </ItemHeader>
            <ItemContent>
              <ItemTitle>{model.name}</ItemTitle>
              <ItemDescription>{model.description}</ItemDescription>
            </ItemContent>
          </Item>
        ))}
      </ItemGroup>
    </div>
  )
}

```

## Link

Use the `render` prop to render the item as a link. The hover and focus states will be applied to the anchor element.

```tsx
import { ChevronRightIcon, ExternalLinkIcon } from "lucide-react"

import {
  Item,
  ItemActions,
  ItemContent,
  ItemDescription,
  ItemTitle,
} from "@/components/ui/item"

export function ItemLink() {
  return (
    <div className="flex w-full max-w-md flex-col gap-4">
      <Item render={<a href="#" />}>
        <ItemContent>
          <ItemTitle>Visit our documentation</ItemTitle>
          <ItemDescription>
            Learn how to get started with our components.
          </ItemDescription>
        </ItemContent>
        <ItemActions>
          <ChevronRightIcon className="size-4" />
        </ItemActions>
      </Item>
      <Item
        variant="outline"
        render={<a href="#" target="_blank" rel="noopener noreferrer" />}
      >
        <ItemContent>
          <ItemTitle>External resource</ItemTitle>
          <ItemDescription>
            Opens in a new tab with security attributes.
          </ItemDescription>
        </ItemContent>
        <ItemActions>
          <ExternalLinkIcon className="size-4" />
        </ItemActions>
      </Item>
    </div>
  )
}

```

```tsx showLineNumbers
<Item render={<a href="/dashboard" />}>
  <ItemMedia variant="icon">
    <HomeIcon />
  </ItemMedia>
  <ItemContent>
    <ItemTitle>Dashboard</ItemTitle>
    <ItemDescription>Overview of your account and activity.</ItemDescription>
  </ItemContent>
</Item>
```

## Dropdown

```tsx
"use client"

import { ChevronDownIcon } from "lucide-react"

import {
  Avatar,
  AvatarFallback,
  AvatarImage,
} from "@/components/ui/avatar"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import {
  Item,
  ItemContent,
  ItemDescription,
  ItemMedia,
  ItemTitle,
} from "@/components/ui/item"

const people = [
  {
    username: "shadcn",
    avatar: "https://github.com/shadcn.png",
    email: "shadcn@vercel.com",
  },
  {
    username: "maxleiter",
    avatar: "https://github.com/maxleiter.png",
    email: "maxleiter@vercel.com",
  },
  {
    username: "evilrabbit",
    avatar: "https://github.com/evilrabbit.png",
    email: "evilrabbit@vercel.com",
  },
]

export function ItemDropdown() {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger render={<Button variant="outline" />}>
        Select <ChevronDownIcon />
      </DropdownMenuTrigger>
      <DropdownMenuContent className="w-48" align="end">
        <DropdownMenuGroup>
          {people.map((person) => (
            <DropdownMenuItem key={person.username}>
              <Item size="xs" className="w-full p-2">
                <ItemMedia>
                  <Avatar className="size-[--spacing(6.5)]">
                    <AvatarImage src={person.avatar} className="grayscale" />
                    <AvatarFallback>{person.username.charAt(0)}</AvatarFallback>
                  </Avatar>
                </ItemMedia>
                <ItemContent className="gap-0">
                  <ItemTitle>{person.username}</ItemTitle>
                  <ItemDescription className="leading-none">
                    {person.email}
                  </ItemDescription>
                </ItemContent>
              </Item>
            </DropdownMenuItem>
          ))}
        </DropdownMenuGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

```

## RTL

To enable RTL support in shadcn/ui, see the [RTL configuration guide](/docs/rtl).

```tsx
"use client"

import * as React from "react"
import { BadgeCheckIcon, ChevronRightIcon } from "lucide-react"

import {
  useTranslation,
  type Translations,
} from "@/components/language-selector"
import { Button } from "@/components/ui/button"
import {
  Item,
  ItemActions,
  ItemContent,
  ItemDescription,
  ItemMedia,
  ItemTitle,
} from "@/components/ui/item"

const translations: Translations = {
  en: {
    dir: "ltr",
    values: {
      basicItem: "Basic Item",
      basicItemDesc: "A simple item with title and description.",
      action: "Action",
      verifiedTitle: "Your profile has been verified.",
    },
  },
  ar: {
    dir: "rtl",
    values: {
      basicItem: "عنصر أساسي",
      basicItemDesc: "عنصر بسيط يحتوي على عنوان ووصف.",
      action: "إجراء",
      verifiedTitle: "تم التحقق من ملفك الشخصي.",
    },
  },
  he: {
    dir: "rtl",
    values: {
      basicItem: "פריט בסיסי",
      basicItemDesc: "פריט פשוט עם כותרת ותיאור.",
      action: "פעולה",
      verifiedTitle: "הפרופיל שלך אומת.",
    },
  },
}

export function ItemRtl() {
  const { dir, t } = useTranslation(translations, "ar")

  return (
    <div className="flex w-full max-w-md flex-col gap-6" dir={dir}>
      <Item variant="outline" dir={dir}>
        <ItemContent>
          <ItemTitle>{t.basicItem}</ItemTitle>
          <ItemDescription>{t.basicItemDesc}</ItemDescription>
        </ItemContent>
        <ItemActions>
          <Button variant="outline" size="sm">
            {t.action}
          </Button>
        </ItemActions>
      </Item>
      <Item variant="outline" size="sm" render={<a href="#" />} dir={dir}>
        <ItemMedia>
          <BadgeCheckIcon className="size-5" />
        </ItemMedia>
        <ItemContent>
          <ItemTitle>{t.verifiedTitle}</ItemTitle>
        </ItemContent>
        <ItemActions>
          <ChevronRightIcon className="size-4" />
        </ItemActions>
      </Item>
    </div>
  )
}

```

## API Reference

### Item

The main component for displaying content with media, title, description, and actions.

| Prop      | Type                                | Default     |
| --------- | ----------------------------------- | ----------- |
| `variant` | `"default" \| "outline" \| "muted"` | `"default"` |
| `size`    | `"default" \| "sm" \| "xs"`         | `"default"` |
| `render`  | `React.ReactElement`                |             |

### ItemGroup

A container that groups related items together with consistent styling.

```tsx
<ItemGroup>
  <Item />
  <Item />
</ItemGroup>
```

### ItemSeparator

A separator between items in a group.

```tsx
<ItemGroup>
  <Item />
  <ItemSeparator />
  <Item />
</ItemGroup>
```

### ItemMedia

Use `ItemMedia` to display media content such as icons, images, or avatars.

| Prop      | Type                             | Default     |
| --------- | -------------------------------- | ----------- |
| `variant` | `"default" \| "icon" \| "image"` | `"default"` |

```tsx
<ItemMedia variant="icon">
  <Icon />
</ItemMedia>
```

```tsx
<ItemMedia variant="image">
  <img src="..." alt="..." />
</ItemMedia>
```

### ItemContent

Wraps the title and description of the item.

```tsx
<ItemContent>
  <ItemTitle>Title</ItemTitle>
  <ItemDescription>Description</ItemDescription>
</ItemContent>
```

### ItemTitle

Displays the title of the item.

```tsx
<ItemTitle>Item Title</ItemTitle>
```

### ItemDescription

Displays the description of the item.

```tsx
<ItemDescription>Item description</ItemDescription>
```

### ItemActions

Container for action buttons or other interactive elements.

```tsx
<ItemActions>
  <Button>Action</Button>
</ItemActions>
```

### ItemHeader

Displays a header above the item content.

```tsx
<Item>
  <ItemHeader>Header</ItemHeader>
  <ItemContent>...</ItemContent>
</Item>
```

### ItemFooter

Displays a footer below the item content.

```tsx
<Item>
  <ItemContent>...</ItemContent>
  <ItemFooter>Footer</ItemFooter>
</Item>
```
