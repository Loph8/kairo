import { DemoSection } from './components/DemoSection'
import { FAQ } from './components/FAQ'
import { Features } from './components/Features'
import { FinalCTA } from './components/FinalCTA'
import { Hero } from './components/Hero'
import { HowItWorks } from './components/HowItWorks'
import { PrivacySection } from './components/PrivacySection'
import { SiteFooter } from './components/SiteFooter'
import { SiteHeader } from './components/SiteHeader'
import { Starfield } from './components/Starfield'

export default function App() {
  return (
    <>
      <Starfield />
      <a className="skip-link" href="#main">Skip to content</a>
      <SiteHeader />
      <main id="main" tabIndex={-1}>
        <span id="top" />
        <Hero />
        <HowItWorks />
        <DemoSection />
        <Features />
        <PrivacySection />
        <FAQ />
        <FinalCTA />
      </main>
      <SiteFooter />
    </>
  )
}
