import { ChangeDetectionStrategy, Component, computed, signal } from '@angular/core';
import { addIcons } from 'ionicons';
import { flash } from 'ionicons/icons';
import {
  IonButton,
  IonChip,
  IonContent,
  IonHeader,
  IonIcon,
  IonItem,
  IonLabel,
  IonList,
  IonNote,
  IonText,
  IonTitle,
  IonToolbar,
} from '@ionic/angular/standalone';
import { Device } from '@capacitor/device';

import { environment, firebaseConfig } from '../../environments/environment';

interface InfoItem {
  label: string;
  value: string;
}

@Component({
  selector: 'app-about',
  imports: [
    IonHeader,
    IonToolbar,
    IonTitle,
    IonContent,
    IonList,
    IonItem,
    IonLabel,
    IonNote,
    IonText,
    IonButton,
    IonChip,
    IonIcon,
  ],
  templateUrl: './about.page.html',
  styleUrl: './about.page.scss',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class AboutPage {
  readonly stack: readonly InfoItem[] = [
    { label: 'Angular', value: '22 · zoneless' },
    { label: 'Ionic', value: 'v9 pre-release' },
    { label: 'Native', value: 'Capacitor (Android / iOS)' },
    { label: 'Build', value: 'esbuild application builder' },
    { label: 'Tests', value: 'Vitest + jsdom' },
    { label: 'Toolchain', value: 'Ubuntu 26.04 Docker image' },
  ];

  readonly buildMode = environment.production ? 'production' : 'development';
  readonly firebaseProjectId = firebaseConfig.projectId;

  // Live runtime identity — the quickest way to confirm *which* build you are looking at. @capacitor/device reports
  // android/ios (with the OS version and device model) on a real device, and "web" in a browser, so the same screen
  // tells you whether you are testing the native Capacitor build or just the web preview.
  readonly runtime = signal<InfoItem[]>([{ label: 'Platform', value: 'loading…' }]);

  readonly taps = signal(0);
  readonly doubled = computed(() => this.taps() * 2);

  constructor() {
    addIcons({ flash });
    void this.loadRuntime();
  }

  private async loadRuntime(): Promise<void> {
    try {
      const info = await Device.getInfo();
      const os = `${info.operatingSystem} ${info.osVersion}`.trim();
      this.runtime.set([
        { label: 'Platform', value: info.platform },
        { label: 'Operating system', value: os || '—' },
        { label: 'Model', value: info.model || '—' },
        { label: 'Web view', value: info.webViewVersion || '—' },
      ]);
    } catch {
      // Never let a device-info hiccup break the page; just show that it was unavailable.
      this.runtime.set([{ label: 'Platform', value: 'unavailable' }]);
    }
  }

  tap(): void {
    this.taps.update((value) => value + 1);
  }

  reset(): void {
    this.taps.set(0);
  }
}
