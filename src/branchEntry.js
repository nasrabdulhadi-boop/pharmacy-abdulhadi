import {branchIdFromSearch} from './branchWorkspace.js';

if (['staff','recover','mail'].includes(new URLSearchParams(location.search).get('workspace'))) {
  import('./StaffEntry.jsx');
} else if (branchIdFromSearch(window.location.search)) {
  import('./BranchEntry.jsx');
} else {
  import('./main.jsx');
}
