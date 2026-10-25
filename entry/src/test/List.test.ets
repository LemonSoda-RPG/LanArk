import archiveModelTest from './ArchiveModel.test';
import archiveRowKeyTest from './ArchiveRowKey.test';
import gridColumnsTest from './GridColumns.test';
import pageImageQueueTest from './PageImageQueue.test';
import serverProfileEditTest from './ServerProfileEdit.test';

export default function testsuite() {
  archiveModelTest();
  archiveRowKeyTest();
  gridColumnsTest();
  pageImageQueueTest();
  serverProfileEditTest();
}
