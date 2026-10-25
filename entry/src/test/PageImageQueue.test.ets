import { describe, expect, it } from '@ohos/hypium';
import {
  AbortableRequest,
  PageImageQueue
} from '../main/ets/data/network/PageImageQueue';

function sleep(milliseconds: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(() => {
      resolve();
    }, milliseconds);
  });
}

/** Stands in for a page request so the abort can be observed. */
class FakeRequest implements AbortableRequest {
  aborted: boolean = false;

  isAborted(): boolean {
    return this.aborted;
  }

  abort(): void {
    this.aborted = true;
  }
}

function newQueue(): PageImageQueue {
  return PageImageQueue.create((message: string): void => {});
}

/**
 * A document that could not be read left every page of the next one queued and
 * never started, because the abandoned request held the queue's single slot.
 * These cases pin the slot accounting that fixed it.
 */
export default function pageImageQueueTest() {
  describe('pageImageQueue', () => {
    it('grants the slot to an idle queue', 0, async () => {
      const queue: PageImageQueue = newQueue();
      const ticket: number = await queue.acquire(false);
      expect(ticket > 0).assertTrue();
    });

    it('never makes the page being read wait', 0, async () => {
      const queue: PageImageQueue = newQueue();
      await queue.acquire(false);
      const pending: Promise<number> = queue.acquire(false);
      const ticket: number = await Promise.race([
        queue.acquire(true),
        sleep(200).then(() => -2)
      ]);
      expect(ticket > 0).assertTrue();
      queue.reset();
      await pending;
    });

    it('holds a queued preload until the slot is released', 0, async () => {
      const queue: PageImageQueue = newQueue();
      const first: number = await queue.acquire(false);
      let second: number = 0;
      const pending: Promise<void> = queue.acquire(false).then((ticket: number) => {
        second = ticket;
      });
      await sleep(150);
      expect(second).assertEqual(0);
      queue.release(first, false);
      await pending;
      expect(second > 0).assertTrue();
    });

    it('lets a queued preload give up when the document changes', 0, async () => {
      const queue: PageImageQueue = newQueue();
      await queue.acquire(false);
      const waiting: Promise<number> = queue.acquire(false);
      await sleep(120);
      queue.reset();
      expect(await waiting).assertEqual(-1);
    });

    // The regression: the slot was held by a request that never settled, so the
    // next document never got a turn.
    it('frees the slot a dead document was holding', 0, async () => {
      const queue: PageImageQueue = newQueue();
      await queue.acquire(false);
      queue.reset();
      const ticket: number = await Promise.race([
        queue.acquire(false),
        sleep(200).then(() => -2)
      ]);
      expect(ticket > 0).assertTrue();
    });

    it('kills the requests of the document that went away', 0, async () => {
      const queue: PageImageQueue = newQueue();
      const ticket: number = await queue.acquire(true);
      const request: FakeRequest = new FakeRequest();
      queue.trackRequest(ticket, request);
      queue.reset();
      expect(request.isAborted()).assertTrue();
    });

    it('leaves a finished request alone when the document changes', 0, async () => {
      const queue: PageImageQueue = newQueue();
      const ticket: number = await queue.acquire(true);
      const request: FakeRequest = new FakeRequest();
      queue.trackRequest(ticket, request);
      queue.untrackRequest(ticket);
      queue.release(ticket, true);
      queue.reset();
      expect(request.isAborted()).assertFalse();
    });

    it('ignores a late release from the previous document', 0, async () => {
      const queue: PageImageQueue = newQueue();
      const stale: number = await queue.acquire(false);
      queue.reset();
      const fresh: number = await queue.acquire(false);
      // The dead document's request settles late; it must not hand the slot of
      // the page that is running now to the next caller.
      queue.release(stale, false);
      let waiting: number = 0;
      const pending: Promise<void> = queue.acquire(false).then((ticket: number) => {
        waiting = ticket;
      });
      await sleep(150);
      expect(waiting).assertEqual(0);
      queue.release(fresh, false);
      await pending;
      expect(waiting > 0).assertTrue();
    });
  });
}
