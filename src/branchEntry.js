import {branchIdFromSearch} from './branchWorkspace.js';

if (branchIdFromSearch(window.location.search)) {
  import('./BranchEntry.jsx');
} else {
  import('./main.jsx');
}
