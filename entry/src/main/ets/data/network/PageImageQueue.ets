/** A request the queue can kill when the document it belongs to goes away. */
export interface AbortableRequest {
  isAborted(): boolean;
  abort(): void;
}

/** Where the queue writes its diagnostic lines. Silent by default. */
export type QueueLog = (message: string) => void;

// How long a queued preload waits before checking its turn again. Short enough
// to start the next page promptly, long enough not to spin.
const PAGE_QUEUE_POLL_MS: number = 50;

/**
 * Serialises page-image downloads, with the page being read going first.
 *
 * Every page of a document used to start downloading at once, so the reader
 * shared the connection with three to eight pages behind it and the page on
 * screen took as long as any of them. Staggering the starts did not help: a page
 * takes seconds, so a delay of milliseconds left them all in flight together.
 *
 * So the downloads are queued. A page the user is looking at never queues — the
 * bandwidth belongs to it — and a preloading page waits its turn, one at a time.
 * The queue is ordered by distance from the current page, and a queued page that
 * wakes up while the current page is fetching steps aside again.
 *
 * A ticket belongs to the document that asked for it: `reset` drops the ones
 * still waiting and kills the requests that are running, so a page the server
 * never answers cannot hold the single slot for the document opened next.
 */
export class PageImageQueue {
  private waiting: Array<number> = [];
  private sequence: number = 0;
  /** The ticket holding the single preload slot, or 0 when the slot is free. */
  private busyTicket: number = 0;
  /** Tickets fetching the page on screen; a preload defers to every one. */
  private priorityTickets: Array<number> = [];
  /**
   * Bumped when a new document opens. A waiter from an earlier generation gives
   * up instead of waiting for a turn that no longer exists.
   */
  private generation: number = 0;
  /** Requests a document can still have killed, by ticket. */
  private abortable: Map<number, AbortableRequest> = new Map<number, AbortableRequest>();
  private log: QueueLog = (message: string): void => {};

  /** Builds a queue that reports what it is doing through `log`. */
  static create(log: QueueLog): PageImageQueue {
    const queue: PageImageQueue = new PageImageQueue();
    queue.log = log;
    return queue;
  }

  /** Resolves with the ticket to hand back to `release`, or -1 when dropped. */
  async acquire(highPriority: boolean): Promise<number> {
    this.sequence += 1;
    const ticket: number = this.sequence;
    const generation: number = this.generation;
    if (highPriority) {
      this.priorityTickets.push(ticket);
      this.log(`page image ${ticket} runs immediately (page being read, ` +
        `active=${this.priorityTickets.length})`);
      return ticket;
    }
    this.waiting.push(ticket);
    this.log(`page image ${ticket} queued at position ${this.waiting.length}`);
    while (this.generation === generation && !this.mayRun(ticket)) {
      await this.pause();
    }
    this.waiting = this.waiting.filter((item: number) => item !== ticket);
    if (this.generation !== generation) {
      this.log(`page image ${ticket} dropped with the document it belonged to`);
      return -1;
    }
    this.busyTicket = ticket;
    this.log(`page image ${ticket} started (${this.waiting.length} still waiting)`);
    return ticket;
  }

  release(ticket: number, highPriority: boolean): void {
    if (highPriority) {
      // The page on screen is done; a queued preload may take the bandwidth.
      const slot: number = this.priorityTickets.indexOf(ticket);
      if (slot < 0) {
        // A reset already gave this slot back.
        return;
      }
      this.priorityTickets.splice(slot, 1);
      this.log(`page image ${ticket} finished (page being read)`);
      return;
    }
    if (this.busyTicket !== ticket) {
      // A reset already took the slot back, so this late release must not free
      // the slot of the page that is running now.
      return;
    }
    this.busyTicket = 0;
    this.log(`page image ${ticket} finished`);
  }

  /** Registers the request a ticket is waiting on, so it can be killed. */
  trackRequest(ticket: number, request: AbortableRequest): void {
    this.abortable.set(ticket, request);
  }

  untrackRequest(ticket: number): void {
    this.abortable.delete(ticket);
  }

  /**
   * Kills what the document that just went away left behind, instead of waiting
   * for it to answer.
   *
   * Opening a document and closing one both call this: a page request must not
   * outlive the document it belongs to. Killing it is what makes the next
   * document work at all — the request would otherwise hold the single preload
   * slot until it settled, which for a page the server cannot produce is never,
   * and every later page would queue behind it and never start. Tickets still
   * waiting from the previous document are dropped at the same time, so they
   * stop polling for a turn that no longer exists.
   */
  reset(): void {
    const dropped: number = this.waiting.length;
    const killing: Array<AbortableRequest> = [];
    this.abortable.forEach((request: AbortableRequest) => {
      killing.push(request);
    });
    this.abortable.clear();
    this.generation += 1;
    this.waiting = [];
    this.busyTicket = 0;
    this.priorityTickets = [];
    for (const request of killing) {
      request.abort();
    }
    this.log(`killed ${killing.length} request(s), dropped ${dropped} waiting (document changed)`);
  }

  /** A preloading page defers to the page on screen whenever it is fetching. */
  private isCurrentPageFetching(): boolean {
    return this.priorityTickets.length > 0;
  }

  private mayRun(ticket: number): boolean {
    if (this.isCurrentPageFetching() || this.busyTicket !== 0) {
      return false;
    }
    return this.waiting.length > 0 && this.waiting[0] === ticket;
  }

  private pause(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, PAGE_QUEUE_POLL_MS);
    });
  }
}
