<script>
  // Open Graph + Twitter Card tags for rich link previews (iMessage, Slack,
  // Discord, X, etc.). Each marketing page renders one with its own title,
  // description, and path; the <title> itself stays on the page.
  let {
    title,
    description,
    path = '/',
    image = '/images/vibes-share-card.jpg',
    imageWidth = 1200,
    imageHeight = 630,
    imageAlt = 'The Vibes logo — a neon V on a dark background.'
  } = $props();

  const SITE = 'https://vibes.opentangle.com';
  const url = SITE + path;
  const imageUrl = image.startsWith('http') ? image : SITE + image;
</script>

<svelte:head>
  <link rel="canonical" href={url} />
  <meta property="og:type" content="website" />
  <meta property="og:site_name" content="Vibes" />
  <meta property="og:title" content={title} />
  <meta property="og:description" content={description} />
  <meta property="og:url" content={url} />
  <meta property="og:image" content={imageUrl} />
  <meta property="og:image:width" content={imageWidth} />
  <meta property="og:image:height" content={imageHeight} />
  <meta property="og:image:alt" content={imageAlt} />
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content={title} />
  <meta name="twitter:description" content={description} />
  <meta name="twitter:image" content={imageUrl} />
</svelte:head>
